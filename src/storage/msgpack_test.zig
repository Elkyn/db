const std = @import("std");
const testing = std.testing;
const value_mod = @import("value.zig");
const msgpack_mod = @import("msgpack.zig");

const Value = value_mod.Value;
const MessagePack = msgpack_mod.MessagePack;

test "msgpack: serialize and deserialize null" {
    const allocator = testing.allocator;
    
    const val = Value{ .null = {} };
    const msgpack = try MessagePack.serialize(allocator, val);
    defer allocator.free(msgpack);
    
    try testing.expectEqual(@as(usize, 1), msgpack.len);
    try testing.expectEqual(@as(u8, 0xc0), msgpack[0]);
    
    const decoded = try MessagePack.deserialize(allocator, msgpack);
    try testing.expectEqual(Value.null, decoded);
}

test "msgpack: serialize and deserialize booleans" {
    const allocator = testing.allocator;
    
    // Test true
    {
        const val = Value{ .boolean = true };
        const msgpack = try MessagePack.serialize(allocator, val);
        defer allocator.free(msgpack);
        
        try testing.expectEqual(@as(usize, 1), msgpack.len);
        try testing.expectEqual(@as(u8, 0xc3), msgpack[0]);
        
        const decoded = try MessagePack.deserialize(allocator, msgpack);
        try testing.expectEqual(true, decoded.boolean);
    }
    
    // Test false
    {
        const val = Value{ .boolean = false };
        const msgpack = try MessagePack.serialize(allocator, val);
        defer allocator.free(msgpack);
        
        try testing.expectEqual(@as(usize, 1), msgpack.len);
        try testing.expectEqual(@as(u8, 0xc2), msgpack[0]);
        
        const decoded = try MessagePack.deserialize(allocator, msgpack);
        try testing.expectEqual(false, decoded.boolean);
    }
}

test "msgpack: serialize and deserialize numbers" {
    const allocator = testing.allocator;
    
    // Test various numbers
    const test_cases = [_]f64{
        0.0,
        42.0,
        -17.5,
        3.14159,
        1e10,
        -1e-10,
    };
    
    for (test_cases) |num| {
        const val = Value{ .number = num };
        const msgpack = try MessagePack.serialize(allocator, val);
        defer allocator.free(msgpack);
        
        // Should be float64 format (9 bytes: 1 format + 8 data)
        try testing.expectEqual(@as(usize, 9), msgpack.len);
        try testing.expectEqual(@as(u8, 0xcb), msgpack[0]);
        
        const decoded = try MessagePack.deserialize(allocator, msgpack);
        try testing.expectApproxEqAbs(num, decoded.number, 1e-10);
    }
}

test "msgpack: serialize and deserialize strings" {
    const allocator = testing.allocator;
    
    // Test short string (fixstr)
    {
        const val = Value{ .string = "hello" };
        const msgpack = try MessagePack.serialize(allocator, val);
        defer allocator.free(msgpack);
        
        try testing.expectEqual(@as(usize, 6), msgpack.len); // 1 byte header + 5 bytes string
        try testing.expectEqual(@as(u8, 0xa5), msgpack[0]); // 0xa0 | 5
        try testing.expectEqualStrings("hello", msgpack[1..]);
        
        var decoded = try MessagePack.deserialize(allocator, msgpack);
        defer decoded.deinit(allocator);
        try testing.expectEqualStrings("hello", decoded.string);
    }
    
    // Test longer string (str8)
    {
        const long_str = "a" ** 100;
        const val = Value{ .string = long_str };
        const msgpack = try MessagePack.serialize(allocator, val);
        defer allocator.free(msgpack);
        
        try testing.expectEqual(@as(usize, 102), msgpack.len); // 1 format + 1 length + 100 data
        try testing.expectEqual(@as(u8, 0xd9), msgpack[0]);
        try testing.expectEqual(@as(u8, 100), msgpack[1]);
        
        var decoded = try MessagePack.deserialize(allocator, msgpack);
        defer decoded.deinit(allocator);
        try testing.expectEqualStrings(long_str, decoded.string);
    }
}

test "msgpack: serialize and deserialize arrays" {
    const allocator = testing.allocator;
    
    var arr = std.ArrayList(Value).init(allocator);
    defer arr.deinit();
    
    try arr.append(Value{ .number = 1.0 });
    try arr.append(Value{ .string = "test" });
    try arr.append(Value{ .boolean = true });
    try arr.append(Value{ .null = {} });
    
    const val = Value{ .array = arr };
    const msgpack = try MessagePack.serialize(allocator, val);
    defer allocator.free(msgpack);
    
    // Should start with fixarray format
    try testing.expectEqual(@as(u8, 0x94), msgpack[0]); // 0x90 | 4
    
    var decoded = try MessagePack.deserialize(allocator, msgpack);
    defer decoded.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 4), decoded.array.items.len);
    try testing.expectEqual(@as(f64, 1.0), decoded.array.items[0].number);
    try testing.expectEqualStrings("test", decoded.array.items[1].string);
    try testing.expectEqual(true, decoded.array.items[2].boolean);
    try testing.expectEqual(Value.null, decoded.array.items[3]);
}

test "msgpack: serialize and deserialize objects" {
    const allocator = testing.allocator;
    
    var obj = std.StringHashMap(Value).init(allocator);
    defer obj.deinit();
    
    try obj.put("name", Value{ .string = "Alice" });
    try obj.put("age", Value{ .number = 30.0 });
    try obj.put("active", Value{ .boolean = true });
    
    const val = Value{ .object = obj };
    const msgpack = try MessagePack.serialize(allocator, val);
    defer allocator.free(msgpack);
    
    // Should start with fixmap format
    try testing.expectEqual(@as(u8, 0x83), msgpack[0]); // 0x80 | 3
    
    var decoded = try MessagePack.deserialize(allocator, msgpack);
    defer decoded.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 3), decoded.object.count());
    try testing.expectEqualStrings("Alice", decoded.object.get("name").?.string);
    try testing.expectEqual(@as(f64, 30.0), decoded.object.get("age").?.number);
    try testing.expectEqual(true, decoded.object.get("active").?.boolean);
}

test "msgpack: serialize and deserialize nested structures" {
    const allocator = testing.allocator;
    
    // Create nested object
    var inner_obj = std.StringHashMap(Value).init(allocator);
    defer inner_obj.deinit();
    try inner_obj.put("city", Value{ .string = "New York" });
    try inner_obj.put("zip", Value{ .number = 10001 });
    
    var outer_obj = std.StringHashMap(Value).init(allocator);
    defer outer_obj.deinit();
    try outer_obj.put("name", Value{ .string = "Bob" });
    try outer_obj.put("address", Value{ .object = inner_obj });
    
    const val = Value{ .object = outer_obj };
    const msgpack = try MessagePack.serialize(allocator, val);
    defer allocator.free(msgpack);
    
    var decoded = try MessagePack.deserialize(allocator, msgpack);
    defer decoded.deinit(allocator);
    
    try testing.expectEqualStrings("Bob", decoded.object.get("name").?.string);
    const address = decoded.object.get("address").?.object;
    try testing.expectEqualStrings("New York", address.get("city").?.string);
    try testing.expectEqual(@as(f64, 10001), address.get("zip").?.number);
}

test "msgpack: size comparison with JSON" {
    const allocator = testing.allocator;
    
    // Create a typical data structure
    var obj = std.StringHashMap(Value).init(allocator);
    defer obj.deinit();
    
    try obj.put("id", Value{ .number = 12345 });
    try obj.put("name", Value{ .string = "John Doe" });
    try obj.put("email", Value{ .string = "john@example.com" });
    try obj.put("age", Value{ .number = 35 });
    try obj.put("active", Value{ .boolean = true });
    try obj.put("balance", Value{ .number = 1234.56 });
    
    const val = Value{ .object = obj };
    
    // Serialize to JSON
    const json = try val.toJson(allocator);
    defer allocator.free(json);
    
    // Serialize to MessagePack
    const msgpack = try val.toMsgPack(allocator);
    defer allocator.free(msgpack);
    
    // MessagePack should be significantly smaller
    std.debug.print("\nSize comparison:\n", .{});
    std.debug.print("JSON size: {d} bytes\n", .{json.len});
    std.debug.print("MessagePack size: {d} bytes\n", .{msgpack.len});
    std.debug.print("Reduction: {d:.1}%\n", .{
        (1.0 - @as(f64, @floatFromInt(msgpack.len)) / @as(f64, @floatFromInt(json.len))) * 100.0
    });
    
    // Verify both can be deserialized correctly
    var json_decoded = try Value.fromJson(allocator, json);
    defer json_decoded.deinit(allocator);
    
    var msgpack_decoded = try Value.fromMsgPack(allocator, msgpack);
    defer msgpack_decoded.deinit(allocator);
    
    // Both should have the same data
    try testing.expectEqual(@as(usize, 6), json_decoded.object.count());
    try testing.expectEqual(@as(usize, 6), msgpack_decoded.object.count());
}