const std = @import("std");

/// Represents all possible value types in the database
pub const Value = union(enum) {
    null: void,
    boolean: bool,
    number: f64,
    string: []const u8,
    object: std.StringHashMap(Value),
    array: std.ArrayList(Value),

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .object => |*obj| {
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    var val = entry.value_ptr.*;
                    val.deinit(allocator);
                }
                obj.deinit();
            },
            .array => |*arr| {
                for (arr.items) |*item| {
                    var val = item.*;
                    val.deinit(allocator);
                }
                arr.deinit();
            },
            else => {},
        }
    }

    /// Serialize value to JSON bytes
    pub fn toJson(self: Value, allocator: std.mem.Allocator) ![]const u8 {
        var array_list = std.ArrayList(u8).init(allocator);
        defer array_list.deinit();

        try self.writeJson(array_list.writer());
        return try array_list.toOwnedSlice();
    }

    fn writeJson(self: Value, writer: anytype) !void {
        switch (self) {
            .null => try writer.writeAll("null"),
            .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .number => |n| try std.fmt.format(writer, "{d}", .{n}),
            .string => |s| try std.json.encodeJsonString(s, .{}, writer),
            .object => |obj| {
                try writer.writeByte('{');
                var first = true;
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (!first) try writer.writeByte(',');
                    first = false;
                    try std.json.encodeJsonString(entry.key_ptr.*, .{}, writer);
                    try writer.writeByte(':');
                    try entry.value_ptr.*.writeJson(writer);
                }
                try writer.writeByte('}');
            },
            .array => |arr| {
                try writer.writeByte('[');
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try writer.writeByte(',');
                    try item.writeJson(writer);
                }
                try writer.writeByte(']');
            },
        }
    }

    /// Parse JSON bytes into a Value
    pub fn fromJson(allocator: std.mem.Allocator, json: []const u8) !Value {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
        defer parsed.deinit();
        
        return try fromJsonValue(allocator, parsed.value);
    }

    fn fromJsonValue(allocator: std.mem.Allocator, json_value: std.json.Value) !Value {
        return switch (json_value) {
            .null => Value{ .null = {} },
            .bool => |b| Value{ .boolean = b },
            .integer => |i| Value{ .number = @floatFromInt(i) },
            .float => |f| Value{ .number = f },
            .number_string => |s| Value{ .number = try std.fmt.parseFloat(f64, s) },
            .string => |s| Value{ .string = try allocator.dupe(u8, s) },
            .object => |obj| blk: {
                var new_obj = std.StringHashMap(Value).init(allocator);
                errdefer new_obj.deinit();
                
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    const value = try fromJsonValue(allocator, entry.value_ptr.*);
                    try new_obj.put(key, value);
                }
                
                break :blk Value{ .object = new_obj };
            },
            .array => |arr| blk: {
                var new_arr = std.ArrayList(Value).init(allocator);
                errdefer new_arr.deinit();
                
                for (arr.items) |item| {
                    const value = try fromJsonValue(allocator, item);
                    try new_arr.append(value);
                }
                
                break :blk Value{ .array = new_arr };
            },
        };
    }

    /// Serialize value to MessagePack bytes
    pub fn toMessagePack(self: Value, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        try writeMessagePack(self, buffer.writer());
        return try buffer.toOwnedSlice();
    }
    
    /// Parse MessagePack bytes into a Value
    pub fn fromMessagePack(allocator: std.mem.Allocator, data: []const u8) !Value {
        var parser = MessagePackParser{ .data = data, .pos = 0 };
        return try parser.parseValue(allocator);
    }
    
    fn writeMessagePack(self: Value, writer: anytype) !void {
        switch (self) {
            .null => try writer.writeByte(0xc0), // MessagePack nil
            .boolean => |b| try writer.writeByte(if (b) 0xc3 else 0xc2), // true/false
            .number => |n| {
                // For simplicity, always encode as float64
                try writer.writeByte(0xcb);
                try writer.writeInt(u64, @bitCast(n), .big);
            },
            .string => |s| {
                if (s.len <= 31) {
                    // fixstr
                    try writer.writeByte(@as(u8, 0xa0) | @as(u8, @intCast(s.len)));
                } else if (s.len <= 255) {
                    // str 8
                    try writer.writeByte(0xd9);
                    try writer.writeByte(@intCast(s.len));
                } else if (s.len <= 65535) {
                    // str 16
                    try writer.writeByte(0xda);
                    try writer.writeInt(u16, @intCast(s.len), .big);
                } else {
                    // str 32
                    try writer.writeByte(0xdb);
                    try writer.writeInt(u32, @intCast(s.len), .big);
                }
                try writer.writeAll(s);
            },
            .array => |arr| {
                if (arr.items.len <= 15) {
                    // fixarray
                    try writer.writeByte(@as(u8, 0x90) | @as(u8, @intCast(arr.items.len)));
                } else if (arr.items.len <= 65535) {
                    // array 16
                    try writer.writeByte(0xdc);
                    try writer.writeInt(u16, @intCast(arr.items.len), .big);
                } else {
                    // array 32
                    try writer.writeByte(0xdd);
                    try writer.writeInt(u32, @intCast(arr.items.len), .big);
                }
                for (arr.items) |item| {
                    try writeMessagePack(item, writer);
                }
            },
            .object => |obj| {
                const count = obj.count();
                if (count <= 15) {
                    // fixmap
                    try writer.writeByte(@as(u8, 0x80) | @as(u8, @intCast(count)));
                } else if (count <= 65535) {
                    // map 16
                    try writer.writeByte(0xde);
                    try writer.writeInt(u16, @intCast(count), .big);
                } else {
                    // map 32
                    try writer.writeByte(0xdf);
                    try writer.writeInt(u32, @intCast(count), .big);
                }
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    // Write key as string
                    const key_value = Value{ .string = entry.key_ptr.* };
                    try writeMessagePack(key_value, writer);
                    // Write value
                    try writeMessagePack(entry.value_ptr.*, writer);
                }
            },
        }
    }

    /// Clone a value (deep copy)
    pub fn clone(self: Value, allocator: std.mem.Allocator) !Value {
        return switch (self) {
            .null => Value{ .null = {} },
            .boolean => |b| Value{ .boolean = b },
            .number => |n| Value{ .number = n },
            .string => |s| Value{ .string = try allocator.dupe(u8, s) },
            .object => |obj| {
                var new_obj = std.StringHashMap(Value).init(allocator);
                errdefer {
                    var iter = new_obj.iterator();
                    while (iter.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        var val = entry.value_ptr.*;
                        val.deinit(allocator);
                    }
                    new_obj.deinit();
                }

                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                    errdefer allocator.free(key_copy);
                    
                    const val_copy = try entry.value_ptr.*.clone(allocator);
                    errdefer {
                        var val_mut = val_copy;
                        val_mut.deinit(allocator);
                    }
                    
                    try new_obj.put(key_copy, val_copy);
                }
                
                return Value{ .object = new_obj };
            },
            .array => |arr| {
                var new_arr = std.ArrayList(Value).init(allocator);
                errdefer {
                    for (new_arr.items) |*item| {
                        item.deinit(allocator);
                    }
                    new_arr.deinit();
                }

                for (arr.items) |item| {
                    const item_copy = try item.clone(allocator);
                    try new_arr.append(item_copy);
                }
                
                return Value{ .array = new_arr };
            },
        };
    }
};

const MessagePackParser = struct {
    data: []const u8,
    pos: usize,
    
    fn parseByte(self: *MessagePackParser) !u8 {
        if (self.pos >= self.data.len) return error.UnexpectedEnd;
        const byte = self.data[self.pos];
        self.pos += 1;
        return byte;
    }
    
    fn parseBytes(self: *MessagePackParser, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return error.UnexpectedEnd;
        const bytes = self.data[self.pos..self.pos + len];
        self.pos += len;
        return bytes;
    }
    
    fn parseU16(self: *MessagePackParser) !u16 {
        const bytes = try self.parseBytes(2);
        return std.mem.readInt(u16, bytes[0..2], .big);
    }
    
    fn parseU32(self: *MessagePackParser) !u32 {
        const bytes = try self.parseBytes(4);
        return std.mem.readInt(u32, bytes[0..4], .big);
    }
    
    fn parseF64(self: *MessagePackParser) !f64 {
        const bytes = try self.parseBytes(8);
        const bits = std.mem.readInt(u64, bytes[0..8], .big);
        return @bitCast(bits);
    }
    
    fn parseValue(self: *MessagePackParser, allocator: std.mem.Allocator) !Value {
        const format = try self.parseByte();
        
        return switch (format) {
            0xc0 => Value{ .null = {} }, // nil
            0xc2 => Value{ .boolean = false }, // false
            0xc3 => Value{ .boolean = true }, // true
            
            // Numbers
            0x00...0x7f => Value{ .number = @floatFromInt(format) }, // positive fixint
            0xe0...0xff => Value{ .number = @as(f64, @floatFromInt(@as(i8, @bitCast(format)))) }, // negative fixint
            0xca => blk: { // float32
                const bytes = try self.parseBytes(4);
                const bits = std.mem.readInt(u32, bytes[0..4], .big);
                break :blk Value{ .number = @as(f64, @floatCast(@as(f32, @bitCast(bits)))) };
            },
            0xcb => Value{ .number = try self.parseF64() }, // float64
            0xcc => Value{ .number = @floatFromInt(try self.parseByte()) }, // uint8
            0xcd => Value{ .number = @floatFromInt(try self.parseU16()) }, // uint16
            0xce => Value{ .number = @floatFromInt(try self.parseU32()) }, // uint32
            0xd0 => Value{ .number = @floatFromInt(@as(i8, @bitCast(try self.parseByte()))) }, // int8
            0xd1 => Value{ .number = @floatFromInt(@as(i16, @bitCast(try self.parseU16()))) }, // int16
            0xd2 => Value{ .number = @floatFromInt(@as(i32, @bitCast(try self.parseU32()))) }, // int32
            
            // Strings
            0xa0...0xbf => blk: { // fixstr
                const len = format & 0x1f;
                const bytes = try self.parseBytes(len);
                const str = try allocator.dupe(u8, bytes);
                break :blk Value{ .string = str };
            },
            0xd9 => blk: { // str 8
                const len = try self.parseByte();
                const bytes = try self.parseBytes(len);
                const str = try allocator.dupe(u8, bytes);
                break :blk Value{ .string = str };
            },
            0xda => blk: { // str 16
                const len = try self.parseU16();
                const bytes = try self.parseBytes(len);
                const str = try allocator.dupe(u8, bytes);
                break :blk Value{ .string = str };
            },
            0xdb => blk: { // str 32
                const len = try self.parseU32();
                const bytes = try self.parseBytes(len);
                const str = try allocator.dupe(u8, bytes);
                break :blk Value{ .string = str };
            },
            
            // Arrays
            0x90...0x9f => blk: { // fixarray
                const len = format & 0x0f;
                var arr = std.ArrayList(Value).init(allocator);
                errdefer {
                    for (arr.items) |*item| item.deinit(allocator);
                    arr.deinit();
                }
                
                var i: u8 = 0;
                while (i < len) : (i += 1) {
                    const item = try self.parseValue(allocator);
                    try arr.append(item);
                }
                break :blk Value{ .array = arr };
            },
            0xdc => blk: { // array 16
                const len = try self.parseU16();
                var arr = std.ArrayList(Value).init(allocator);
                errdefer {
                    for (arr.items) |*item| item.deinit(allocator);
                    arr.deinit();
                }
                
                var i: u16 = 0;
                while (i < len) : (i += 1) {
                    const item = try self.parseValue(allocator);
                    try arr.append(item);
                }
                break :blk Value{ .array = arr };
            },
            0xdd => blk: { // array 32
                const len = try self.parseU32();
                var arr = std.ArrayList(Value).init(allocator);
                errdefer {
                    for (arr.items) |*item| item.deinit(allocator);
                    arr.deinit();
                }
                
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const item = try self.parseValue(allocator);
                    try arr.append(item);
                }
                break :blk Value{ .array = arr };
            },
            
            // Maps/Objects  
            0x80...0x8f => blk: { // fixmap
                const len = format & 0x0f;
                var obj = std.StringHashMap(Value).init(allocator);
                errdefer {
                    var iter = obj.iterator();
                    while (iter.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        var val = entry.value_ptr.*;
                        val.deinit(allocator);
                    }
                    obj.deinit();
                }
                
                var i: u8 = 0;
                while (i < len) : (i += 1) {
                    const key_val = try self.parseValue(allocator);
                    defer {
                        var key_mut = key_val;
                        key_mut.deinit(allocator);
                    }
                    
                    const key_str = switch (key_val) {
                        .string => |s| try allocator.dupe(u8, s),
                        else => return error.InvalidMapKey,
                    };
                    errdefer allocator.free(key_str);
                    
                    const value = try self.parseValue(allocator);
                    try obj.put(key_str, value);
                }
                break :blk Value{ .object = obj };
            },
            0xde => blk: { // map 16
                const len = try self.parseU16();
                var obj = std.StringHashMap(Value).init(allocator);
                errdefer {
                    var iter = obj.iterator();
                    while (iter.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        var val = entry.value_ptr.*;
                        val.deinit(allocator);
                    }
                    obj.deinit();
                }
                
                var i: u16 = 0;
                while (i < len) : (i += 1) {
                    const key_val = try self.parseValue(allocator);
                    defer {
                        var key_mut = key_val;
                        key_mut.deinit(allocator);
                    }
                    
                    const key_str = switch (key_val) {
                        .string => |s| try allocator.dupe(u8, s),
                        else => return error.InvalidMapKey,
                    };
                    errdefer allocator.free(key_str);
                    
                    const value = try self.parseValue(allocator);
                    try obj.put(key_str, value);
                }
                break :blk Value{ .object = obj };
            },
            0xdf => blk: { // map 32
                const len = try self.parseU32();
                var obj = std.StringHashMap(Value).init(allocator);
                errdefer {
                    var iter = obj.iterator();
                    while (iter.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        var val = entry.value_ptr.*;
                        val.deinit(allocator);
                    }
                    obj.deinit();
                }
                
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const key_val = try self.parseValue(allocator);
                    defer {
                        var key_mut = key_val;
                        key_mut.deinit(allocator);
                    }
                    
                    const key_str = switch (key_val) {
                        .string => |s| try allocator.dupe(u8, s),
                        else => return error.InvalidMapKey,
                    };
                    errdefer allocator.free(key_str);
                    
                    const value = try self.parseValue(allocator);
                    try obj.put(key_str, value);
                }
                break :blk Value{ .object = obj };
            },
            
            else => return error.UnsupportedFormat,
        };
    }
};