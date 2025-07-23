const std = @import("std");
const storage_mod = @import("../storage/storage.zig");
const value_mod = @import("../storage/value.zig");
const event_emitter_mod = @import("../storage/event_emitter.zig");

const Storage = storage_mod.Storage;
const Value = value_mod.Value;
const EventEmitter = event_emitter_mod.EventEmitter;
const Event = event_emitter_mod.Event;

const log = std.log.scoped(.websocket);

// WebSocket opcodes
const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

// WebSocket frame header
const FrameHeader = struct {
    fin: bool,
    opcode: Opcode,
    masked: bool,
    payload_len: u64,
    masking_key: ?[4]u8,
};

pub const WebSocketConnection = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    storage: *Storage,
    event_emitter: *EventEmitter,
    subscriptions: std.ArrayList(u64),
    subscription_paths: std.StringHashMap(u64),
    
    pub fn init(
        allocator: std.mem.Allocator,
        stream: std.net.Stream,
        storage: *Storage,
        event_emitter: *EventEmitter,
    ) WebSocketConnection {
        return .{
            .allocator = allocator,
            .stream = stream,
            .storage = storage,
            .event_emitter = event_emitter,
            .subscriptions = std.ArrayList(u64).init(allocator),
            .subscription_paths = std.StringHashMap(u64).init(allocator),
        };
    }
    
    pub fn deinit(self: *WebSocketConnection) void {
        // Unsubscribe all
        for (self.subscriptions.items) |sub_id| {
            self.event_emitter.unsubscribe(sub_id);
        }
        self.subscriptions.deinit();
        
        // Free path strings
        var iter = self.subscription_paths.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.subscription_paths.deinit();
    }
    
    pub fn handleAfterHandshake(self: *WebSocketConnection) !void {
        // Main message loop (handshake already done in HTTP server)
        while (true) {
            const frame = self.readFrame() catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            
            switch (frame.opcode) {
                .text => {
                    const payload = try self.readPayload(frame);
                    defer self.allocator.free(payload);
                    
                    try self.handleMessage(payload);
                },
                .binary => {
                    // We only support text for now
                    try self.sendError("Binary frames not supported");
                },
                .close => {
                    // Client initiated close
                    break;
                },
                .ping => {
                    const payload = try self.readPayload(frame);
                    defer self.allocator.free(payload);
                    
                    try self.sendPong(payload);
                },
                .pong => {
                    // Ignore pongs
                    _ = try self.readPayload(frame);
                },
                else => {},
            }
        }
    }
    
    fn readFrame(self: *WebSocketConnection) !FrameHeader {
        var header: FrameHeader = undefined;
        
        // Read first 2 bytes
        var header_buf: [2]u8 = undefined;
        const header_read = try self.stream.read(&header_buf);
        if (header_read < 2) return error.IncompleteFrame;
        
        header.fin = (header_buf[0] & 0x80) != 0;
        header.opcode = @enumFromInt(header_buf[0] & 0x0F);
        header.masked = (header_buf[1] & 0x80) != 0;
        
        const payload_len_7 = header_buf[1] & 0x7F;
        
        // Read extended payload length if needed
        if (payload_len_7 < 126) {
            header.payload_len = payload_len_7;
        } else if (payload_len_7 == 126) {
            var len_buf: [2]u8 = undefined;
            const len_read = try self.stream.read(&len_buf);
            if (len_read < 2) return error.IncompleteFrame;
            header.payload_len = std.mem.readInt(u16, &len_buf, .big);
        } else {
            var len_buf: [8]u8 = undefined;
            const len_read = try self.stream.read(&len_buf);
            if (len_read < 8) return error.IncompleteFrame;
            header.payload_len = std.mem.readInt(u64, &len_buf, .big);
        }
        
        // Read masking key if present
        if (header.masked) {
            var mask_buf: [4]u8 = undefined;
            const mask_read = try self.stream.read(&mask_buf);
            if (mask_read < 4) return error.IncompleteFrame;
            header.masking_key = mask_buf;
        } else {
            header.masking_key = null;
        }
        
        return header;
    }
    
    fn readPayload(self: *WebSocketConnection, frame: FrameHeader) ![]u8 {
        // Limit payload size to prevent DoS
        const max_payload_size = 10 * 1024 * 1024; // 10MB
        if (frame.payload_len > max_payload_size) {
            return error.PayloadTooLarge;
        }
        
        const payload = try self.allocator.alloc(u8, frame.payload_len);
        errdefer self.allocator.free(payload);
        
        // Read all data
        var total_read: usize = 0;
        while (total_read < frame.payload_len) {
            const bytes_read = try self.stream.read(payload[total_read..]);
            if (bytes_read == 0) return error.UnexpectedEndOfStream;
            total_read += bytes_read;
        }
        
        // Unmask if needed
        if (frame.masking_key) |mask| {
            for (payload, 0..) |*byte, i| {
                byte.* ^= mask[i % 4];
            }
        }
        
        return payload;
    }
    
    fn sendFrame(self: *WebSocketConnection, opcode: Opcode, payload: []const u8) !void {
        var header: [10]u8 = undefined;
        var header_len: usize = 2;
        
        // FIN = 1, no masking
        header[0] = 0x80 | @as(u8, @intFromEnum(opcode));
        
        if (payload.len < 126) {
            header[1] = @intCast(payload.len);
        } else if (payload.len <= 0xFFFF) {
            header[1] = 126;
            std.mem.writeInt(u16, header[2..4], @intCast(payload.len), .big);
            header_len = 4;
        } else {
            header[1] = 127;
            std.mem.writeInt(u64, header[2..10], payload.len, .big);
            header_len = 10;
        }
        
        _ = try self.stream.write(header[0..header_len]);
        _ = try self.stream.write(payload);
    }
    
    fn sendText(self: *WebSocketConnection, text: []const u8) !void {
        try self.sendFrame(.text, text);
    }
    
    fn sendPong(self: *WebSocketConnection, payload: []const u8) !void {
        try self.sendFrame(.pong, payload);
    }
    
    fn sendError(self: *WebSocketConnection, message: []const u8) !void {
        const response = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"error","message":"{s}"}}
        , .{message});
        defer self.allocator.free(response);
        
        try self.sendText(response);
    }
    
    fn handleMessage(self: *WebSocketConnection, message: []const u8) !void {
        // Parse JSON message
        const parsed = std.json.parseFromSlice(
            struct {
                type: []const u8,
                path: ?[]const u8 = null,
                value: ?std.json.Value = null,
                include_children: ?bool = null,
            },
            self.allocator,
            message,
            .{},
        ) catch {
            try self.sendError("Invalid JSON");
            return;
        };
        defer parsed.deinit();
        
        const msg = parsed.value;
        
        if (std.mem.eql(u8, msg.type, "subscribe")) {
            try self.handleSubscribe(msg.path orelse "/", msg.include_children orelse false);
        } else if (std.mem.eql(u8, msg.type, "unsubscribe")) {
            try self.handleUnsubscribe(msg.path orelse "/");
        } else if (std.mem.eql(u8, msg.type, "get")) {
            try self.handleGet(msg.path orelse "/");
        } else if (std.mem.eql(u8, msg.type, "set")) {
            try self.handleSet(msg.path orelse "/", msg.value);
        } else {
            try self.sendError("Unknown message type");
        }
    }
    
    fn handleSubscribe(self: *WebSocketConnection, path: []const u8, include_children: bool) !void {
        const sub_id = try self.event_emitter.subscribe(
            path,
            webSocketEventListener,
            self,
            include_children
        );
        
        try self.subscriptions.append(sub_id);
        
        // Store path -> subscription_id mapping
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);
        try self.subscription_paths.put(path_copy, sub_id);
        
        const response = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"subscribed","path":"{s}","subscription_id":{}}}
        , .{ path, sub_id });
        defer self.allocator.free(response);
        
        try self.sendText(response);
    }
    
    fn handleUnsubscribe(self: *WebSocketConnection, path: []const u8) !void {
        // Find subscription ID for this path
        const sub_id = self.subscription_paths.get(path) orelse {
            try self.sendError("No subscription found for path");
            return;
        };
        
        // Remove from event emitter
        self.event_emitter.unsubscribe(sub_id);
        
        // Remove from our tracking
        if (self.subscription_paths.fetchRemove(path)) |entry| {
            self.allocator.free(entry.key);
        }
        
        // Remove from subscriptions list
        var i: usize = 0;
        while (i < self.subscriptions.items.len) : (i += 1) {
            if (self.subscriptions.items[i] == sub_id) {
                _ = self.subscriptions.swapRemove(i);
                break;
            }
        }
        
        const response = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"unsubscribed","path":"{s}"}}
        , .{path});
        defer self.allocator.free(response);
        
        try self.sendText(response);
    }
    
    fn handleGet(self: *WebSocketConnection, path: []const u8) !void {
        var value = self.storage.get(path) catch |err| {
            if (err == error.NotFound) {
                try self.sendError("Not found");
            } else {
                try self.sendError("Storage error");
            }
            return;
        };
        defer value.deinit(self.allocator);
        
        const json = try value.toJson(self.allocator);
        defer self.allocator.free(json);
        
        const response = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"value","path":"{s}","value":{s}}}
        , .{ path, json });
        defer self.allocator.free(response);
        
        try self.sendText(response);
    }
    
    fn handleSet(self: *WebSocketConnection, path: []const u8, json_value: ?std.json.Value) !void {
        const json_val = json_value orelse {
            try self.sendError("Missing value for set operation");
            return;
        };
        
        // Convert std.json.Value to our Value type
        const value = try self.jsonValueToValue(json_val);
        defer value.deinit(self.allocator);
        
        // Set in storage
        self.storage.set(path, value) catch |err| {
            const error_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to set value: {}",
                .{err}
            );
            defer self.allocator.free(error_msg);
            try self.sendError(error_msg);
            return;
        };
        
        const response = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"set_success","path":"{s}"}}
        , .{path});
        defer self.allocator.free(response);
        
        try self.sendText(response);
    }
    
    fn jsonValueToValue(self: *WebSocketConnection, json: std.json.Value) !Value {
        switch (json) {
            .null => return Value{ .null = {} },
            .bool => |b| return Value{ .boolean = b },
            .integer => |i| return Value{ .number = @floatFromInt(i) },
            .float => |f| return Value{ .number = f },
            .number_string => |s| {
                const num = std.fmt.parseFloat(f64, s) catch {
                    return error.InvalidNumber;
                };
                return Value{ .number = num };
            },
            .string => |s| {
                const str_copy = try self.allocator.dupe(u8, s);
                return Value{ .string = str_copy };
            },
            .array => |arr| {
                var value_array = std.ArrayList(Value).init(self.allocator);
                errdefer {
                    for (value_array.items) |*item| {
                        item.deinit(self.allocator);
                    }
                    value_array.deinit();
                }
                
                for (arr.items) |item| {
                    const val = try self.jsonValueToValue(item);
                    try value_array.append(val);
                }
                
                return Value{ .array = value_array };
            },
            .object => |obj| {
                var value_map = std.StringHashMap(Value).init(self.allocator);
                errdefer {
                    var iter = value_map.iterator();
                    while (iter.next()) |entry| {
                        self.allocator.free(entry.key_ptr.*);
                        var val = entry.value_ptr.*;
                        val.deinit(self.allocator);
                    }
                    value_map.deinit();
                }
                
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                    errdefer self.allocator.free(key_copy);
                    
                    const val = try self.jsonValueToValue(entry.value_ptr.*);
                    errdefer {
                        var val_mut = val;
                        val_mut.deinit(self.allocator);
                    }
                    
                    try value_map.put(key_copy, val);
                }
                
                return Value{ .object = value_map };
            },
        }
    }
};

fn webSocketEventListener(event: Event, context: ?*anyopaque) void {
    const conn = @as(*WebSocketConnection, @ptrCast(@alignCast(context.?)));
    
    // Convert event to JSON
    const event_json = std.fmt.allocPrint(
        conn.allocator,
        \\{{"type":"event","event_type":"{s}","path":"{s}"}}
    , .{ @tagName(event.type), event.path }) catch {
        log.err("Failed to format event", .{});
        return;
    };
    defer conn.allocator.free(event_json);
    
    conn.sendText(event_json) catch {
        log.err("Failed to send event", .{});
    };
}