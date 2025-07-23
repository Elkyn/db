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