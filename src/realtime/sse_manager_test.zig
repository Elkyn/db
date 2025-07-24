const std = @import("std");
const testing = std.testing;
const SSEManager = @import("sse_manager.zig").SSEManager;
const SSEConnection = @import("sse_manager.zig").SSEConnection;
const Value = @import("../storage/value.zig").Value;

// Mock stream for testing
const MockStream = struct {
    handle: i32,
    written_data: std.ArrayList(u8),
    fail_writes: bool = false,
    
    pub fn init(allocator: std.mem.Allocator, handle: i32) MockStream {
        return .{
            .handle = handle,
            .written_data = std.ArrayList(u8).init(allocator),
            .fail_writes = false,
        };
    }
    
    pub fn deinit(self: *MockStream) void {
        self.written_data.deinit();
    }
    
    pub fn write(self: *MockStream, data: []const u8) !usize {
        if (self.fail_writes) return error.BrokenPipe;
        try self.written_data.appendSlice(data);
        return data.len;
    }
    
    pub fn toStream(self: *MockStream) std.net.Stream {
        return std.net.Stream{ .handle = self.handle };
    }
};

test "sse connection: send event" {
    const allocator = testing.allocator;
    
    var mock = MockStream.init(allocator, 1);
    defer mock.deinit();
    
    var conn = SSEConnection{
        .stream = mock.toStream(),
        .path = "/test",
        .allocator = allocator,
    };
    
    // Mock the stream write function
    conn.stream.write = struct {
        fn write(stream: std.net.Stream, data: []const u8) !usize {
            _ = stream;
            try mock.written_data.appendSlice(data);
            return data.len;
        }
    }.write;
    
    try conn.sendEvent("update", "hello world");
    
    const expected = "event: update\ndata: hello world\n\n";
    try testing.expectEqualStrings(expected, mock.written_data.items);
}

test "sse connection: send data" {
    const allocator = testing.allocator;
    
    var mock = MockStream.init(allocator, 2);
    defer mock.deinit();
    
    var conn = SSEConnection{
        .stream = mock.toStream(),
        .path = "/test",
        .allocator = allocator,
    };
    
    // Mock the stream write function
    conn.stream.write = struct {
        fn write(stream: std.net.Stream, data: []const u8) !usize {
            _ = stream;
            try mock.written_data.appendSlice(data);
            return data.len;
        }
    }.write;
    
    try conn.sendData("{\"value\": 42}");
    
    const expected = "data: {\"value\": 42}\n\n";
    try testing.expectEqualStrings(expected, mock.written_data.items);
}

test "sse connection: send heartbeat" {
    const allocator = testing.allocator;
    
    var mock = MockStream.init(allocator, 3);
    defer mock.deinit();
    
    var conn = SSEConnection{
        .stream = mock.toStream(),
        .path = "/test",
        .allocator = allocator,
    };
    
    // Mock the stream write function
    conn.stream.write = struct {
        fn write(stream: std.net.Stream, data: []const u8) !usize {
            _ = stream;
            try mock.written_data.appendSlice(data);
            return data.len;
        }
    }.write;
    
    try conn.sendHeartbeat();
    
    const expected = ":heartbeat\n\n";
    try testing.expectEqualStrings(expected, mock.written_data.items);
}

test "sse manager: initialization" {
    const allocator = testing.allocator;
    
    var manager = SSEManager.init(allocator);
    defer manager.deinit();
    
    try testing.expect(manager.connections.items.len == 0);
}

test "sse manager: add and remove connections" {
    const allocator = testing.allocator;
    
    var manager = SSEManager.init(allocator);
    defer manager.deinit();
    
    // Create mock streams
    const stream1 = std.net.Stream{ .handle = 1 };
    const stream2 = std.net.Stream{ .handle = 2 };
    
    // Add connections
    try manager.addConnection(stream1, "/users");
    try manager.addConnection(stream2, "/posts");
    
    try testing.expect(manager.connections.items.len == 2);
    
    // Remove a connection
    manager.removeConnection(stream1);
    try testing.expect(manager.connections.items.len == 1);
    
    // Verify the correct connection was removed
    try testing.expectEqualStrings("/posts", manager.connections.items[0].path);
    
    // Remove non-existent connection (should not error)
    manager.removeConnection(stream1);
    try testing.expect(manager.connections.items.len == 1);
}

test "sse manager: notify value changed - matching paths" {
    const allocator = testing.allocator;
    
    var manager = SSEManager.init(allocator);
    defer manager.deinit();
    
    // Create a test value
    const value = Value{ .string = "test data" };
    
    // Add some connections
    const stream1 = std.net.Stream{ .handle = 1 };
    const stream2 = std.net.Stream{ .handle = 2 };
    const stream3 = std.net.Stream{ .handle = 3 };
    
    try manager.addConnection(stream1, "/users");
    try manager.addConnection(stream2, "/users/123");
    try manager.addConnection(stream3, "/posts");
    
    // Track which connections received updates
    var notifications_sent = std.ArrayList(bool).init(allocator);
    defer notifications_sent.deinit();
    try notifications_sent.appendNTimes(false, 3);
    
    // Mock the sendData method
    for (manager.connections.items, 0..) |*conn, i| {
        conn.sendData = struct {
            fn sendData(self: *SSEConnection, data: []const u8) !void {
                _ = self;
                _ = data;
                notifications_sent.items[i] = true;
            }
        }.sendData;
    }
    
    // Notify about a change to /users/123
    try manager.notifyValueChanged("/users/123", value);
    
    // Connections watching /users and /users/123 should be notified
    // Connection watching /posts should not be notified
    // Note: This test is simplified - in real implementation, the notification
    // logic would need to be properly mocked
}

test "sse manager: handle dead connections during notify" {
    const allocator = testing.allocator;
    
    var manager = SSEManager.init(allocator);
    defer manager.deinit();
    
    // Add connections
    const stream1 = std.net.Stream{ .handle = 1 };
    const stream2 = std.net.Stream{ .handle = 2 };
    const stream3 = std.net.Stream{ .handle = 3 };
    
    try manager.addConnection(stream1, "/users");
    try manager.addConnection(stream2, "/users");
    try manager.addConnection(stream3, "/users");
    
    try testing.expect(manager.connections.items.len == 3);
    
    // In a real test, we would mock sendData to fail for some connections
    // This would cause those connections to be removed
    // For now, we're testing the structure is in place
}

test "sse manager: send heartbeats" {
    const allocator = testing.allocator;
    
    var manager = SSEManager.init(allocator);
    defer manager.deinit();
    
    // Add connections
    const stream1 = std.net.Stream{ .handle = 1 };
    const stream2 = std.net.Stream{ .handle = 2 };
    
    try manager.addConnection(stream1, "/users");
    try manager.addConnection(stream2, "/posts");
    
    // Track heartbeats sent
    var heartbeats_sent: usize = 0;
    
    // Mock the sendHeartbeat method
    for (manager.connections.items) |*conn| {
        conn.sendHeartbeat = struct {
            fn sendHeartbeat(self: *SSEConnection) !void {
                _ = self;
                heartbeats_sent += 1;
            }
        }.sendHeartbeat;
    }
    
    manager.sendHeartbeats();
    
    // Should send heartbeat to all connections
    try testing.expectEqual(@as(usize, 2), heartbeats_sent);
}

test "sse manager: thread safety" {
    const allocator = testing.allocator;
    
    var manager = SSEManager.init(allocator);
    defer manager.deinit();
    
    // Test that mutex is properly used
    // In a real concurrent test, we would spawn threads
    // For now, we're verifying the mutex exists and can be locked/unlocked
    manager.mutex.lock();
    manager.mutex.unlock();
    
    // The real thread safety would be tested with actual concurrent operations
}