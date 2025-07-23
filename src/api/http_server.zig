const std = @import("std");
const storage_mod = @import("../storage/storage.zig");
const value_mod = @import("../storage/value.zig");
const event_emitter_mod = @import("../storage/event_emitter.zig");
const websocket_mod = @import("websocket.zig");
const thread_pool_mod = @import("../thread_pool.zig");

const Storage = storage_mod.Storage;
const Value = value_mod.Value;
const EventEmitter = event_emitter_mod.EventEmitter;
const WebSocketConnection = websocket_mod.WebSocketConnection;
const ThreadPool = thread_pool_mod.ThreadPool;

const log = std.log.scoped(.http);

pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    storage: *Storage,
    event_emitter: *EventEmitter,
    server: std.net.Server,
    thread_pool: ThreadPool,
    
    pub fn init(allocator: std.mem.Allocator, storage: *Storage, event_emitter: *EventEmitter, port: u16) !HttpServer {
        const address = try std.net.Address.parseIp("127.0.0.1", port);
        const server = try address.listen(.{
            .reuse_address = true,
        });
        
        // Create thread pool with reasonable number of threads
        const cpu_count = try std.Thread.getCpuCount();
        const thread_count = @max(4, @min(cpu_count * 2, 16)); // Between 4 and 16 threads
        
        return HttpServer{
            .allocator = allocator,
            .storage = storage,
            .event_emitter = event_emitter,
            .server = server,
            .thread_pool = try ThreadPool.init(allocator, thread_count),
        };
    }
    
    pub fn deinit(self: *HttpServer) void {
        self.thread_pool.deinit();
        self.server.deinit();
    }
    
    pub fn start(self: *HttpServer, should_quit: *const std.atomic.Value(bool)) !void {
        log.info("HTTP server listening on port {d}", .{self.server.listen_address.getPort()});
        
        while (!should_quit.load(.acquire)) {
            // Accept with timeout to check for shutdown
            const connection = self.server.accept() catch |err| {
                if (err == error.WouldBlock) {
                    std.time.sleep(10 * std.time.ns_per_ms);
                    continue;
                }
                return err;
            };
            
            // Submit connection to thread pool
            const ctx = try self.allocator.create(ConnectionContext);
            ctx.* = .{
                .server = self,
                .connection = connection,
            };
            
            try self.thread_pool.submit(.{
                .callback = handleConnectionWrapper,
                .context = ctx,
            });
        }
    }
    
    const ConnectionContext = struct {
        server: *HttpServer,
        connection: std.net.Server.Connection,
    };
    
    fn handleConnectionWrapper(context: *anyopaque) void {
        const ctx = @as(*ConnectionContext, @ptrCast(@alignCast(context)));
        defer ctx.server.allocator.destroy(ctx);
        
        handleConnection(ctx.server, ctx.connection) catch |err| {
            log.err("Error handling connection: {}", .{err});
        };
    }
    
    fn handleConnection(server: *HttpServer, connection: std.net.Server.Connection) !void {
        defer connection.stream.close();
        
        // Create arena allocator for this request
        var arena = std.heap.ArenaAllocator.init(server.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();
        
        // Read initial request header (should be enough for most headers)
        var header_buf: [8192]u8 = undefined;
        const initial_read = try connection.stream.read(&header_buf);
        
        if (initial_read == 0) return;
        
        // Check if we have complete headers
        const header_end = std.mem.indexOf(u8, header_buf[0..initial_read], "\r\n\r\n") orelse
            std.mem.indexOf(u8, header_buf[0..initial_read], "\n\n");
        
        if (header_end == null) {
            try sendResponse(connection, 400, "Bad Request", "Headers too large");
            return;
        }
        
        // Parse Content-Length if present
        var content_length: ?usize = null;
        if (std.mem.indexOf(u8, header_buf[0..initial_read], "Content-Length: ")) |cl_start| {
            const cl_line_end = std.mem.indexOfScalarPos(u8, header_buf[0..initial_read], cl_start, '\n') orelse initial_read;
            const cl_value_start = cl_start + "Content-Length: ".len;
            const cl_value = std.mem.trim(u8, header_buf[cl_value_start..cl_line_end], "\r\n ");
            content_length = std.fmt.parseInt(usize, cl_value, 10) catch null;
        }
        
        // Allocate buffer for full request if needed
        var request_data: []u8 = undefined;
        var allocated = false;
        // No need to free - arena will handle it
        
        if (content_length) |cl| {
            const header_end_pos = header_end.? + if (std.mem.indexOf(u8, header_buf[0..initial_read], "\r\n\r\n") != null) 4 else 2;
            const body_in_initial = initial_read - header_end_pos;
            const total_size = header_end_pos + cl;
            
            // Limit request size to prevent DoS
            if (total_size > 10 * 1024 * 1024) { // 10MB limit
                try sendResponse(connection, 413, "Payload Too Large", "");
                return;
            }
            
            if (total_size > header_buf.len) {
                // Need to allocate larger buffer using arena
                request_data = try arena_allocator.alloc(u8, total_size);
                allocated = true;
                @memcpy(request_data[0..initial_read], header_buf[0..initial_read]);
                
                // Read remaining data
                var total_read = initial_read;
                while (total_read < total_size) {
                    const bytes_read = try connection.stream.read(request_data[total_read..]);
                    if (bytes_read == 0) break;
                    total_read += bytes_read;
                }
            } else {
                request_data = header_buf[0..total_size];
            }
        } else {
            request_data = header_buf[0..initial_read];
        }
        
        const request = request_data;
        
        // Parse HTTP request
        var lines = std.mem.tokenizeScalar(u8, request, '\n');
        const request_line = lines.next() orelse return;
        
        var parts = std.mem.tokenizeScalar(u8, request_line, ' ');
        const method = parts.next() orelse return;
        const path = parts.next() orelse return;
        
        // Check for WebSocket upgrade
        if (std.mem.eql(u8, method, "GET") and isWebSocketUpgrade(request)) {
            try handleWebSocketUpgrade(server, connection, request);
            return;
        }
        
        // Route the request
        if (std.mem.eql(u8, method, "GET")) {
            try handleGet(server, connection, path);
        } else if (std.mem.eql(u8, method, "PUT")) {
            try handlePut(server, connection, path, request);
        } else if (std.mem.eql(u8, method, "DELETE")) {
            try handleDelete(server, connection, path);
        } else if (std.mem.eql(u8, method, "PATCH")) {
            try handlePatch(server, connection, path, request);
        } else {
            try sendResponse(connection, 405, "Method Not Allowed", "");
        }
    }
    
    fn handleGet(server: *HttpServer, connection: std.net.Server.Connection, path: []const u8) !void {
        // Remove query params if any
        const clean_path = if (std.mem.indexOf(u8, path, "?")) |idx| path[0..idx] else path;
        
        // Get value from storage
        var value = server.storage.get(clean_path) catch |err| {
            if (err == error.NotFound) {
                try sendResponse(connection, 404, "Not Found", "");
                return;
            }
            try sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        defer value.deinit(server.allocator);
        
        // Convert to JSON using arena allocator
        const json = try value.toJson(arena_allocator);
        // No need to free - arena will clean up
        
        try sendJsonResponse(connection, 200, "OK", json);
    }
    
    fn handlePut(server: *HttpServer, connection: std.net.Server.Connection, path: []const u8, request: []const u8) !void {
        // Find body start (after headers)
        const body_start = std.mem.indexOf(u8, request, "\r\n\r\n") orelse std.mem.indexOf(u8, request, "\n\n") orelse {
            try sendResponse(connection, 400, "Bad Request", "");
            return;
        };
        
        const body = if (std.mem.indexOf(u8, request, "\r\n\r\n")) |idx|
            request[idx + 4 ..]
        else
            request[body_start + 2 ..];
        
        // Parse JSON body
        var value = Value.fromJson(server.allocator, body) catch {
            try sendResponse(connection, 400, "Bad Request", "Invalid JSON");
            return;
        };
        defer value.deinit(server.allocator);
        
        // Store value
        server.storage.set(path, value) catch {
            try sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        
        try sendResponse(connection, 201, "Created", "");
    }
    
    fn handleDelete(server: *HttpServer, connection: std.net.Server.Connection, path: []const u8) !void {
        server.storage.delete(path) catch |err| {
            if (err == error.NotFound) {
                try sendResponse(connection, 404, "Not Found", "");
                return;
            }
            try sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        
        try sendResponse(connection, 204, "No Content", "");
    }
    
    fn handlePatch(server: *HttpServer, connection: std.net.Server.Connection, path: []const u8, request: []const u8) !void {
        // Find body start (after headers)
        const body_start = std.mem.indexOf(u8, request, "\r\n\r\n") orelse std.mem.indexOf(u8, request, "\n\n") orelse {
            try sendResponse(connection, 400, "Bad Request", "");
            return;
        };
        
        const body = if (std.mem.indexOf(u8, request, "\r\n\r\n")) |idx|
            request[idx + 4 ..]
        else
            request[body_start + 2 ..];
        
        // Parse JSON patch body
        var patch_value = Value.fromJson(server.allocator, body) catch {
            try sendResponse(connection, 400, "Bad Request", "Invalid JSON");
            return;
        };
        defer patch_value.deinit(server.allocator);
        
        // Patch must be an object
        if (patch_value != .object) {
            try sendResponse(connection, 400, "Bad Request", "PATCH body must be an object");
            return;
        }
        
        // Get existing value
        var existing = server.storage.get(path) catch |err| {
            if (err == error.NotFound) {
                // If doesn't exist, PATCH creates it with just the patch data
                server.storage.set(path, patch_value) catch {
                    try sendResponse(connection, 500, "Internal Server Error", "");
                    return;
                };
                try sendResponse(connection, 201, "Created", "");
                return;
            }
            try sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        defer existing.deinit(server.allocator);
        
        // Existing value must be an object to patch
        if (existing != .object) {
            try sendResponse(connection, 400, "Bad Request", "Cannot PATCH non-object value");
            return;
        }
        
        // Merge patch into existing object
        const merged = try mergeObjects(server.allocator, existing.object, patch_value.object);
        var merged_value = Value{ .object = merged };
        defer merged_value.deinit(server.allocator);
        
        // Store merged value
        server.storage.set(path, merged_value) catch {
            try sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        
        try sendResponse(connection, 200, "OK", "");
    }
    
    fn mergeObjects(
        allocator: std.mem.Allocator,
        existing: std.StringHashMap(Value),
        patch: std.StringHashMap(Value),
    ) !std.StringHashMap(Value) {
        var result = std.StringHashMap(Value).init(allocator);
        errdefer {
            var iter = result.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                var val = entry.value_ptr.*;
                val.deinit(allocator);
            }
            result.deinit();
        }
        
        // Copy all existing fields
        var existing_iter = existing.iterator();
        while (existing_iter.next()) |entry| {
            const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
            const val_copy = try entry.value_ptr.*.clone(allocator);
            try result.put(key_copy, val_copy);
        }
        
        // Apply patch fields (overwrite or add)
        var patch_iter = patch.iterator();
        while (patch_iter.next()) |entry| {
            // Remove existing value if present
            if (result.fetchRemove(entry.key_ptr.*)) |old| {
                allocator.free(old.key);
                var old_val = old.value;
                old_val.deinit(allocator);
            }
            
            // Add patched value
            const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
            const val_copy = try entry.value_ptr.*.clone(allocator);
            try result.put(key_copy, val_copy);
        }
        
        return result;
    }
    
    fn sendResponse(connection: std.net.Server.Connection, status: u16, status_text: []const u8, body: []const u8) !void {
        // First send headers
        var header_buf: [512]u8 = undefined;
        const headers = try std.fmt.bufPrint(
            &header_buf,
            "HTTP/1.1 {d} {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ status, status_text, body.len }
        );
        
        _ = try connection.stream.write(headers);
        
        // Then send body separately if present
        if (body.len > 0) {
            _ = try connection.stream.write(body);
        }
    }
    
    fn sendJsonResponse(connection: std.net.Server.Connection, status: u16, status_text: []const u8, json: []const u8) !void {
        // First send headers
        var header_buf: [512]u8 = undefined;
        const headers = try std.fmt.bufPrint(
            &header_buf,
            "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ status, status_text, json.len }
        );
        
        _ = try connection.stream.write(headers);
        
        // Then send JSON body
        _ = try connection.stream.write(json);
    }
    
    fn isWebSocketUpgrade(request: []const u8) bool {
        return std.mem.indexOf(u8, request, "Upgrade: websocket") != null;
    }
    
    fn handleWebSocketUpgrade(server: *HttpServer, connection: std.net.Server.Connection, request: []const u8) !void {
        // Extract WebSocket key from request
        var key: ?[]const u8 = null;
        var lines = std.mem.tokenizeScalar(u8, request, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, "\r");
            if (std.mem.startsWith(u8, trimmed, "Sec-WebSocket-Key: ")) {
                key = trimmed["Sec-WebSocket-Key: ".len..];
                break;
            }
        }
        
        const ws_key = key orelse {
            try sendResponse(connection, 400, "Bad Request", "Missing WebSocket key");
            return;
        };
        
        // Generate accept key
        const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var sha1 = std.crypto.hash.Sha1.init(.{});
        sha1.update(ws_key);
        sha1.update(magic);
        
        var hash: [20]u8 = undefined;
        sha1.final(&hash);
        
        var accept_key_buf: [28]u8 = undefined;
        const accept_key = std.base64.standard.Encoder.encode(&accept_key_buf, &hash);
        
        // Send handshake response
        var response_buf: [512]u8 = undefined;
        const response = try std.fmt.bufPrint(
            &response_buf,
            "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n" ++
            "\r\n",
            .{accept_key}
        );
        
        _ = try connection.stream.write(response);
        
        // Create WebSocket connection handler
        var ws_conn = WebSocketConnection.init(
            server.allocator,
            connection.stream,
            server.storage,
            server.event_emitter
        );
        defer ws_conn.deinit();
        
        // Handle the WebSocket connection (handshake already done)
        try ws_conn.handleAfterHandshake();
    }
};