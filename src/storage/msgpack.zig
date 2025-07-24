const std = @import("std");
const value_mod = @import("value.zig");

const Value = value_mod.Value;

/// MessagePack serialization/deserialization for Value type
pub const MessagePack = struct {
    /// Serialize a Value to MessagePack bytes
    pub fn serialize(allocator: std.mem.Allocator, value: Value) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        try serializeValue(&buffer, value);
        return try buffer.toOwnedSlice();
    }
    
    /// Deserialize MessagePack bytes to a Value
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !Value {
        var stream = std.io.fixedBufferStream(data);
        return try deserializeValue(allocator, stream.reader());
    }
    
    fn serializeValue(buffer: *std.ArrayList(u8), value: Value) !void {
        switch (value) {
            .null => try buffer.append(0xc0), // nil format
            .boolean => |b| try buffer.append(if (b) 0xc3 else 0xc2), // true/false format
            .number => |n| {
                // For simplicity, always use float64 format
                try buffer.append(0xcb); // float64 format
                const bytes = @as([8]u8, @bitCast(n));
                // MessagePack uses big-endian
                var i: usize = 8;
                while (i > 0) : (i -= 1) {
                    try buffer.append(bytes[i - 1]);
                }
            },
            .string => |s| {
                // String format depends on length
                if (s.len <= 31) {
                    // fixstr format (101XXXXX)
                    try buffer.append(0xa0 | @as(u8, @intCast(s.len)));
                } else if (s.len <= 255) {
                    // str8 format
                    try buffer.append(0xd9);
                    try buffer.append(@as(u8, @intCast(s.len)));
                } else if (s.len <= 65535) {
                    // str16 format
                    try buffer.append(0xda);
                    const len_bytes = @as([2]u8, @bitCast(@as(u16, @intCast(s.len))));
                    try buffer.append(len_bytes[1]);
                    try buffer.append(len_bytes[0]);
                } else {
                    // str32 format
                    try buffer.append(0xdb);
                    const len_bytes = @as([4]u8, @bitCast(@as(u32, @intCast(s.len))));
                    var i: usize = 4;
                    while (i > 0) : (i -= 1) {
                        try buffer.append(len_bytes[i - 1]);
                    }
                }
                try buffer.appendSlice(s);
            },
            .object => |obj| {
                // Map format depends on size
                const size = obj.count();
                if (size <= 15) {
                    // fixmap format (1000XXXX)
                    try buffer.append(0x80 | @as(u8, @intCast(size)));
                } else if (size <= 65535) {
                    // map16 format
                    try buffer.append(0xde);
                    const size_bytes = @as([2]u8, @bitCast(@as(u16, @intCast(size))));
                    try buffer.append(size_bytes[1]);
                    try buffer.append(size_bytes[0]);
                } else {
                    // map32 format
                    try buffer.append(0xdf);
                    const size_bytes = @as([4]u8, @bitCast(@as(u32, @intCast(size))));
                    var i: usize = 4;
                    while (i > 0) : (i -= 1) {
                        try buffer.append(size_bytes[i - 1]);
                    }
                }
                
                // Serialize key-value pairs
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    // Key (always string)
                    try serializeValue(buffer, .{ .string = entry.key_ptr.* });
                    // Value
                    try serializeValue(buffer, entry.value_ptr.*);
                }
            },
            .array => |arr| {
                // Array format depends on size
                const size = arr.items.len;
                if (size <= 15) {
                    // fixarray format (1001XXXX)
                    try buffer.append(0x90 | @as(u8, @intCast(size)));
                } else if (size <= 65535) {
                    // array16 format
                    try buffer.append(0xdc);
                    const size_bytes = @as([2]u8, @bitCast(@as(u16, @intCast(size))));
                    try buffer.append(size_bytes[1]);
                    try buffer.append(size_bytes[0]);
                } else {
                    // array32 format
                    try buffer.append(0xdd);
                    const size_bytes = @as([4]u8, @bitCast(@as(u32, @intCast(size))));
                    var i: usize = 4;
                    while (i > 0) : (i -= 1) {
                        try buffer.append(size_bytes[i - 1]);
                    }
                }
                
                // Serialize elements
                for (arr.items) |item| {
                    try serializeValue(buffer, item);
                }
            },
        }
    }
    
    fn deserializeValue(allocator: std.mem.Allocator, reader: anytype) anyerror!Value {
        const format = try reader.readByte();
        
        // Positive fixint (0xxxxxxx)
        if (format & 0x80 == 0) {
            return Value{ .number = @as(f64, @floatFromInt(format)) };
        }
        
        // Negative fixint (111xxxxx)
        if (format & 0xe0 == 0xe0) {
            const val = @as(i8, @bitCast(format));
            return Value{ .number = @as(f64, @floatFromInt(val)) };
        }
        
        // Fixmap (1000xxxx)
        if (format & 0xf0 == 0x80) {
            const size = format & 0x0f;
            return try deserializeMap(allocator, reader, size);
        }
        
        // Fixarray (1001xxxx)
        if (format & 0xf0 == 0x90) {
            const size = format & 0x0f;
            return try deserializeArray(allocator, reader, size);
        }
        
        // Fixstr (101xxxxx)
        if (format & 0xe0 == 0xa0) {
            const size = format & 0x1f;
            return try deserializeString(allocator, reader, size);
        }
        
        return switch (format) {
            0xc0 => Value{ .null = {} }, // nil
            0xc2 => Value{ .boolean = false }, // false
            0xc3 => Value{ .boolean = true }, // true
            
            // Numbers
            0xca => blk: { // float32
                var bytes: [4]u8 = undefined;
                var i: usize = 4;
                while (i > 0) : (i -= 1) {
                    bytes[i - 1] = try reader.readByte();
                }
                const val = @as(f32, @bitCast(bytes));
                break :blk Value{ .number = @as(f64, val) };
            },
            0xcb => blk: { // float64
                var bytes: [8]u8 = undefined;
                var i: usize = 8;
                while (i > 0) : (i -= 1) {
                    bytes[i - 1] = try reader.readByte();
                }
                break :blk Value{ .number = @as(f64, @bitCast(bytes)) };
            },
            0xcc => Value{ .number = @as(f64, @floatFromInt(try reader.readByte())) }, // uint8
            0xcd => blk: { // uint16
                const high = try reader.readByte();
                const low = try reader.readByte();
                const val = (@as(u16, high) << 8) | @as(u16, low);
                break :blk Value{ .number = @as(f64, @floatFromInt(val)) };
            },
            0xce => blk: { // uint32
                var val: u32 = 0;
                var i: usize = 0;
                while (i < 4) : (i += 1) {
                    val = (val << 8) | @as(u32, try reader.readByte());
                }
                break :blk Value{ .number = @as(f64, @floatFromInt(val)) };
            },
            0xcf => blk: { // uint64
                var val: u64 = 0;
                var i: usize = 0;
                while (i < 8) : (i += 1) {
                    val = (val << 8) | @as(u64, try reader.readByte());
                }
                break :blk Value{ .number = @as(f64, @floatFromInt(val)) };
            },
            0xd0 => blk: { // int8
                const val = @as(i8, @bitCast(try reader.readByte()));
                break :blk Value{ .number = @as(f64, @floatFromInt(val)) };
            },
            0xd1 => blk: { // int16
                const high = try reader.readByte();
                const low = try reader.readByte();
                const bytes = [2]u8{ low, high };
                const val = @as(i16, @bitCast(bytes));
                break :blk Value{ .number = @as(f64, @floatFromInt(val)) };
            },
            0xd2 => blk: { // int32
                var bytes: [4]u8 = undefined;
                var i: usize = 4;
                while (i > 0) : (i -= 1) {
                    bytes[i - 1] = try reader.readByte();
                }
                const val = @as(i32, @bitCast(bytes));
                break :blk Value{ .number = @as(f64, @floatFromInt(val)) };
            },
            0xd3 => blk: { // int64
                var bytes: [8]u8 = undefined;
                var i: usize = 8;
                while (i > 0) : (i -= 1) {
                    bytes[i - 1] = try reader.readByte();
                }
                const val = @as(i64, @bitCast(bytes));
                break :blk Value{ .number = @as(f64, @floatFromInt(val)) };
            },
            
            // Strings
            0xd9 => blk: { // str8
                const size = try reader.readByte();
                break :blk try deserializeString(allocator, reader, size);
            },
            0xda => blk: { // str16
                const high = try reader.readByte();
                const low = try reader.readByte();
                const size = (@as(u16, high) << 8) | @as(u16, low);
                break :blk try deserializeString(allocator, reader, size);
            },
            0xdb => blk: { // str32
                var size: u32 = 0;
                var i: usize = 0;
                while (i < 4) : (i += 1) {
                    size = (size << 8) | @as(u32, try reader.readByte());
                }
                break :blk try deserializeString(allocator, reader, size);
            },
            
            // Arrays
            0xdc => blk: { // array16
                const high = try reader.readByte();
                const low = try reader.readByte();
                const size = (@as(u16, high) << 8) | @as(u16, low);
                break :blk try deserializeArray(allocator, reader, size);
            },
            0xdd => blk: { // array32
                var size: u32 = 0;
                var i: usize = 0;
                while (i < 4) : (i += 1) {
                    size = (size << 8) | @as(u32, try reader.readByte());
                }
                break :blk try deserializeArray(allocator, reader, size);
            },
            
            // Maps
            0xde => blk: { // map16
                const high = try reader.readByte();
                const low = try reader.readByte();
                const size = (@as(u16, high) << 8) | @as(u16, low);
                break :blk try deserializeMap(allocator, reader, size);
            },
            0xdf => blk: { // map32
                var size: u32 = 0;
                var i: usize = 0;
                while (i < 4) : (i += 1) {
                    size = (size << 8) | @as(u32, try reader.readByte());
                }
                break :blk try deserializeMap(allocator, reader, size);
            },
            
            else => error.InvalidMessagePackFormat,
        };
    }
    
    fn deserializeString(allocator: std.mem.Allocator, reader: anytype, size: anytype) !Value {
        const str = try allocator.alloc(u8, size);
        errdefer allocator.free(str);
        
        _ = try reader.read(str);
        return Value{ .string = str };
    }
    
    fn deserializeArray(allocator: std.mem.Allocator, reader: anytype, size: anytype) !Value {
        var arr = std.ArrayList(Value).init(allocator);
        errdefer {
            for (arr.items) |*item| {
                item.deinit(allocator);
            }
            arr.deinit();
        }
        
        var i: @TypeOf(size) = 0;
        while (i < size) : (i += 1) {
            const item = try deserializeValue(allocator, reader);
            try arr.append(item);
        }
        
        return Value{ .array = arr };
    }
    
    fn deserializeMap(allocator: std.mem.Allocator, reader: anytype, size: anytype) !Value {
        var map = std.StringHashMap(Value).init(allocator);
        errdefer {
            var iter = map.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                var val = entry.value_ptr.*;
                val.deinit(allocator);
            }
            map.deinit();
        }
        
        var i: @TypeOf(size) = 0;
        while (i < size) : (i += 1) {
            // Key must be a string
            const key_value = try deserializeValue(allocator, reader);
            if (key_value != .string) {
                var kv = key_value;
                kv.deinit(allocator);
                return error.InvalidMessagePackFormat;
            }
            
            const value = try deserializeValue(allocator, reader);
            try map.put(key_value.string, value);
        }
        
        return Value{ .object = map };
    }
};