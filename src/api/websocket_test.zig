const std = @import("std");
const testing = std.testing;
const WebSocketConnection = @import("websocket.zig").WebSocketConnection;
const Storage = @import("../storage/storage.zig").Storage;
const Value = @import("../storage/value.zig").Value;
const EventEmitter = @import("../storage/event_emitter.zig").EventEmitter;

// Mock stream for testing
const MockStream = struct {
    read_buffer: []const u8,
    write_buffer: std.ArrayList(u8),
    read_pos: usize = 0,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, read_data: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .read_buffer = read_data,
            .write_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.write_buffer.deinit();
    }

    pub fn read(self: *Self, buffer: []u8) !usize {
        const remaining = self.read_buffer.len - self.read_pos;
        if (remaining == 0) return error.EndOfStream;
        
        const to_read = @min(buffer.len, remaining);
        @memcpy(buffer[0..to_read], self.read_buffer[self.read_pos..self.read_pos + to_read]);
        self.read_pos += to_read;
        return to_read;
    }

    pub fn write(self: *Self, bytes: []const u8) !usize {
        try self.write_buffer.appendSlice(bytes);
        return bytes.len;
    }
};

// Helper to create WebSocket frames
fn createTextFrame(allocator: std.mem.Allocator, text: []const u8, masked: bool) ![]u8 {
    var frame = std.ArrayList(u8).init(allocator);
    defer frame.deinit();
    
    // FIN = 1, opcode = 1 (text)
    try frame.append(0x81);
    
    // Payload length
    if (text.len <= 125) {
        const len_byte: u8 = if (masked) 0x80 | @as(u8, @intCast(text.len)) else @as(u8, @intCast(text.len));
        try frame.append(len_byte);
    } else if (text.len <= 65535) {
        try frame.append(if (masked) 0xFE else 0x7E);
        try frame.append(@as(u8, @intCast((text.len >> 8) & 0xFF)));
        try frame.append(@as(u8, @intCast(text.len & 0xFF)));
    } else {
        return error.PayloadTooLarge;
    }
    
    // Masking key (if masked)
    if (masked) {
        const mask = [_]u8{ 0x12, 0x34, 0x56, 0x78 };
        try frame.appendSlice(&mask);
        
        // Masked payload
        for (text, 0..) |byte, i| {
            try frame.append(byte ^ mask[i % 4]);
        }
    } else {
        try frame.appendSlice(text);
    }
    
    return frame.toOwnedSlice();
}

test "websocket: parse text frame" {
    const allocator = testing.allocator;
    
    // Create a simple text frame
    const frame_data = try createTextFrame(allocator, "Hello", true);
    defer allocator.free(frame_data);
    
    var stream = try MockStream.init(allocator, frame_data);
    defer stream.deinit();
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Read frame
    const frame = try ws.readFrame();
    defer allocator.free(frame.payload);
    
    try testing.expectEqual(@as(u8, 1), frame.opcode); // Text frame
    try testing.expectEqualStrings("Hello", frame.payload);
}

test "websocket: send text message" {
    const allocator = testing.allocator;
    
    var stream = try MockStream.init(allocator, "");
    defer stream.deinit();
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Send text message
    try ws.sendText("Hello Client");
    
    // Verify frame structure
    const sent = stream.write_buffer.items;
    try testing.expect(sent.len >= 2);
    try testing.expectEqual(@as(u8, 0x81), sent[0]); // FIN=1, opcode=1
    try testing.expectEqual(@as(u8, 12), sent[1]); // Payload length
    try testing.expectEqualStrings("Hello Client", sent[2..]);
}

test "websocket: handle subscribe message" {
    const allocator = testing.allocator;
    
    const subscribe_msg = 
        \\{"type": "subscribe", "path": "/users", "include_children": true}
    ;
    const frame_data = try createTextFrame(allocator, subscribe_msg, true);
    defer allocator.free(frame_data);
    
    var stream = try MockStream.init(allocator, frame_data);
    defer stream.deinit();
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Handle the frame
    try ws.handleConnection();
    
    // Verify response
    const response = stream.write_buffer.items;
    const response_text = response[2..]; // Skip frame header
    
    try testing.expect(std.mem.indexOf(u8, response_text, "\"type\":\"subscribed\"") != null);
    try testing.expect(std.mem.indexOf(u8, response_text, "\"path\":\"/users\"") != null);
    try testing.expect(std.mem.indexOf(u8, response_text, "\"subscription_id\":") != null);
}

test "websocket: handle get message" {
    const allocator = testing.allocator;
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    // Store test data
    try storage.set("/test/data", Value{ .string = "test value" });
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    const get_msg = 
        \\{"type": "get", "path": "/test/data"}
    ;
    const frame_data = try createTextFrame(allocator, get_msg, true);
    defer allocator.free(frame_data);
    
    var stream = try MockStream.init(allocator, frame_data);
    defer stream.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Handle the frame
    try ws.handleConnection();
    
    // Verify response
    const response = stream.write_buffer.items;
    const response_text = response[2..]; // Skip frame header
    
    try testing.expect(std.mem.indexOf(u8, response_text, "\"type\":\"value\"") != null);
    try testing.expect(std.mem.indexOf(u8, response_text, "\"path\":\"/test/data\"") != null);
    try testing.expect(std.mem.indexOf(u8, response_text, "\"value\":\"test value\"") != null);
}

test "websocket: handle set message" {
    const allocator = testing.allocator;
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    const set_msg = 
        \\{"type": "set", "path": "/test/new", "value": {"name": "Alice"}}
    ;
    const frame_data = try createTextFrame(allocator, set_msg, true);
    defer allocator.free(frame_data);
    
    var stream = try MockStream.init(allocator, frame_data);
    defer stream.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Handle the frame
    try ws.handleConnection();
    
    // Verify response
    const response = stream.write_buffer.items;
    const response_text = response[2..]; // Skip frame header
    
    try testing.expect(std.mem.indexOf(u8, response_text, "\"type\":\"success\"") != null);
    
    // Verify value was stored
    const stored = try storage.get("/test/new");
    defer stored.deinit(allocator);
    try testing.expect(stored == .object);
    try testing.expectEqualStrings("Alice", stored.object.get("name").?.string);
}

test "websocket: handle ping frame" {
    const allocator = testing.allocator;
    
    // Create ping frame (opcode = 9)
    var ping_frame = std.ArrayList(u8).init(allocator);
    defer ping_frame.deinit();
    
    try ping_frame.append(0x89); // FIN=1, opcode=9 (ping)
    try ping_frame.append(0x80 | 4); // Masked, length=4
    try ping_frame.appendSlice(&[_]u8{ 0x12, 0x34, 0x56, 0x78 }); // Mask
    try ping_frame.appendSlice(&[_]u8{ 0x12, 0x34, 0x56, 0x78 }); // Masked "ping"
    
    const frame_data = try ping_frame.toOwnedSlice();
    defer allocator.free(frame_data);
    
    var stream = try MockStream.init(allocator, frame_data);
    defer stream.deinit();
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Handle the frame
    try ws.handleConnection();
    
    // Verify pong response
    const response = stream.write_buffer.items;
    try testing.expect(response.len >= 2);
    try testing.expectEqual(@as(u8, 0x8A), response[0]); // FIN=1, opcode=10 (pong)
}

test "websocket: handle close frame" {
    const allocator = testing.allocator;
    
    // Create close frame (opcode = 8)
    var close_frame = std.ArrayList(u8).init(allocator);
    defer close_frame.deinit();
    
    try close_frame.append(0x88); // FIN=1, opcode=8 (close)
    try close_frame.append(0x82); // Masked, length=2
    try close_frame.appendSlice(&[_]u8{ 0x12, 0x34, 0x56, 0x78 }); // Mask
    try close_frame.append(0x03 ^ 0x12); // Status code 1000 (normal) high byte
    try close_frame.append(0xE8 ^ 0x34); // Status code low byte
    
    const frame_data = try close_frame.toOwnedSlice();
    defer allocator.free(frame_data);
    
    var stream = try MockStream.init(allocator, frame_data);
    defer stream.deinit();
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Handle should complete without error
    try ws.handleConnection();
    
    // Verify close response was sent
    const response = stream.write_buffer.items;
    try testing.expect(response.len >= 2);
    try testing.expectEqual(@as(u8, 0x88), response[0]); // Close frame
}

test "websocket: handle invalid message type" {
    const allocator = testing.allocator;
    
    const invalid_msg = 
        \\{"type": "invalid_type", "path": "/test"}
    ;
    const frame_data = try createTextFrame(allocator, invalid_msg, true);
    defer allocator.free(frame_data);
    
    var stream = try MockStream.init(allocator, frame_data);
    defer stream.deinit();
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Handle the frame
    try ws.handleConnection();
    
    // Verify error response
    const response = stream.write_buffer.items;
    const response_text = response[2..]; // Skip frame header
    
    try testing.expect(std.mem.indexOf(u8, response_text, "\"type\":\"error\"") != null);
    try testing.expect(std.mem.indexOf(u8, response_text, "Unknown message type") != null);
}

test "websocket: handle malformed JSON" {
    const allocator = testing.allocator;
    
    const malformed_msg = "{invalid json}";
    const frame_data = try createTextFrame(allocator, malformed_msg, true);
    defer allocator.free(frame_data);
    
    var stream = try MockStream.init(allocator, frame_data);
    defer stream.deinit();
    
    // Setup test environment
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    var ws = WebSocketConnection.init(allocator, &stream, &storage, &event_emitter);
    defer ws.deinit();
    
    // Handle the frame
    try ws.handleConnection();
    
    // Verify error response
    const response = stream.write_buffer.items;
    const response_text = response[2..]; // Skip frame header
    
    try testing.expect(std.mem.indexOf(u8, response_text, "\"type\":\"error\"") != null);
}