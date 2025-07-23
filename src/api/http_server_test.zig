const std = @import("std");
const testing = std.testing;
const Storage = @import("../storage/storage.zig").Storage;
const Value = @import("../storage/value.zig").Value;
const HttpServer = @import("http_server.zig").HttpServer;
const EventEmitter = @import("../storage/event_emitter.zig").EventEmitter;

// Mock connection for testing
const MockConnection = struct {
    read_buffer: []const u8,
    write_buffer: std.ArrayList(u8),
    read_pos: usize = 0,
    closed: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, read_data: []const u8) !Self {
        return Self{
            .read_buffer = read_data,
            .write_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.write_buffer.deinit();
    }

    pub const Stream = struct {
        conn: *MockConnection,

        pub fn read(self: Stream, buffer: []u8) !usize {
            const remaining = self.conn.read_buffer.len - self.conn.read_pos;
            if (remaining == 0) return 0;
            
            const to_read = @min(buffer.len, remaining);
            @memcpy(buffer[0..to_read], self.conn.read_buffer[self.conn.read_pos..self.conn.read_pos + to_read]);
            self.conn.read_pos += to_read;
            return to_read;
        }

        pub fn write(self: Stream, bytes: []const u8) !usize {
            try self.conn.write_buffer.appendSlice(bytes);
            return bytes.len;
        }
    };

    pub fn stream(self: *Self) Stream {
        return .{ .conn = self };
    }

    pub fn close(self: *Self) void {
        self.closed = true;
    }
};

test "http_server: GET request returns stored value" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    // Store test data
    try storage.set("/test/key", Value{ .string = "test value" });
    
    // Create HTTP server
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with GET request
    const request = "GET /test/key HTTP/1.1\r\n\r\n";
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 200 OK") != null);
    try testing.expect(std.mem.indexOf(u8, response, "\"test value\"") != null);
    try testing.expect(conn.closed);
}

test "http_server: GET request returns 404 for missing key" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with GET request
    const request = "GET /missing/key HTTP/1.1\r\n\r\n";
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 404 Not Found") != null);
    try testing.expect(conn.closed);
}

test "http_server: PUT request stores value" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with PUT request
    const body = "{\"name\": \"test\"}";
    const request = std.fmt.allocPrint(allocator, 
        "PUT /users/123 HTTP/1.1\r\nContent-Length: {d}\r\n\r\n{s}", 
        .{ body.len, body }
    ) catch unreachable;
    defer allocator.free(request);
    
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 201 Created") != null);
    
    // Verify value was stored
    const stored = try storage.get("/users/123");
    defer stored.deinit(allocator);
    try testing.expect(stored == .object);
    const name = stored.object.get("name").?;
    try testing.expectEqualStrings("test", name.string);
}

test "http_server: PATCH request updates value" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    // Store initial data
    var initial = Value{ .object = std.StringHashMap(Value).init(allocator) };
    try initial.object.put("name", Value{ .string = "Alice" });
    try initial.object.put("age", Value{ .number = 25 });
    try storage.set("/users/123", initial);
    initial.deinit(allocator);
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with PATCH request
    const body = "{\"age\": 26}";
    const request = std.fmt.allocPrint(allocator, 
        "PATCH /users/123 HTTP/1.1\r\nContent-Length: {d}\r\n\r\n{s}", 
        .{ body.len, body }
    ) catch unreachable;
    defer allocator.free(request);
    
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 200 OK") != null);
    
    // Verify value was updated
    const updated = try storage.get("/users/123");
    defer updated.deinit(allocator);
    try testing.expect(updated == .object);
    try testing.expectEqualStrings("Alice", updated.object.get("name").?.string);
    try testing.expectEqual(@as(f64, 26), updated.object.get("age").?.number);
}

test "http_server: DELETE request removes value" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    // Store initial data
    try storage.set("/test/key", Value{ .string = "to be deleted" });
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with DELETE request
    const request = "DELETE /test/key HTTP/1.1\r\n\r\n";
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 204 No Content") != null);
    
    // Verify value was deleted
    const result = storage.get("/test/key");
    try testing.expectError(error.NotFound, result);
}

test "http_server: invalid HTTP method returns 405" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with invalid method
    const request = "POST /test HTTP/1.1\r\n\r\n";
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 405 Method Not Allowed") != null);
}

test "http_server: malformed request returns 400" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with malformed request
    const request = "INVALID REQUEST\r\n\r\n";
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 400 Bad Request") != null);
}

test "http_server: PUT with invalid JSON returns 400" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with invalid JSON
    const body = "{invalid json}";
    const request = std.fmt.allocPrint(allocator, 
        "PUT /test HTTP/1.1\r\nContent-Length: {d}\r\n\r\n{s}", 
        .{ body.len, body }
    ) catch unreachable;
    defer allocator.free(request);
    
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 400 Bad Request") != null);
}

test "http_server: large request body handling" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create large JSON body (1MB)
    const large_body = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(large_body);
    @memset(large_body, 'x');
    
    // Wrap in JSON
    const json_body = try std.fmt.allocPrint(allocator, "{{\"data\": \"{s}\"}}", .{large_body});
    defer allocator.free(json_body);
    
    const request = try std.fmt.allocPrint(allocator, 
        "PUT /large HTTP/1.1\r\nContent-Length: {d}\r\n\r\n{s}", 
        .{ json_body.len, json_body }
    );
    defer allocator.free(request);
    
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection
    try server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    });
    
    // Verify response
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 201 Created") != null);
}

test "http_server: WebSocket upgrade request" {
    const allocator = testing.allocator;
    
    // Setup storage
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var server = HttpServer.init(allocator, &storage, &event_emitter, 0);
    
    // Create mock connection with WebSocket upgrade
    const request = 
        \\GET /ws HTTP/1.1
        \\Upgrade: websocket
        \\Connection: Upgrade
        \\Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
        \\Sec-WebSocket-Version: 13
        \\
        \\
    ;
    var conn = try MockConnection.init(allocator, request);
    defer conn.deinit();
    
    // Handle the connection (it will upgrade to WebSocket)
    server.handleConnection(.{
        .stream = conn.stream(),
        .close = conn.close,
    }) catch |err| {
        // WebSocket handling might fail in test environment
        if (err != error.EndOfStream) return err;
    };
    
    // Verify upgrade response was sent
    const response = conn.write_buffer.items;
    try testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 101 Switching Protocols") != null);
    try testing.expect(std.mem.indexOf(u8, response, "Upgrade: websocket") != null);
}