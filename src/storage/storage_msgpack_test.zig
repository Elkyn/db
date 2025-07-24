const std = @import("std");
const testing = std.testing;
const Storage = @import("storage.zig").Storage;
const Value = @import("value.zig").Value;

test "storage: uses MessagePack internally for primitives" {
    const allocator = testing.allocator;
    
    // Create temporary test directory
    const test_dir = "test_msgpack_storage";
    try std.fs.cwd().makeDir(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    // Test various primitive types
    const test_cases = [_]struct {
        path: []const u8,
        value: Value,
    }{
        .{ .path = "/string", .value = .{ .string = "Hello MessagePack!" } },
        .{ .path = "/number", .value = .{ .number = 42.5 } },
        .{ .path = "/boolean", .value = .{ .boolean = true } },
        .{ .path = "/null", .value = .{ .null = {} } },
    };
    
    // Set values
    for (test_cases) |tc| {
        try storage.set(tc.path, tc.value);
    }
    
    // Retrieve and verify values
    for (test_cases) |tc| {
        var retrieved = try storage.get(tc.path);
        defer retrieved.deinit(allocator);
        
        switch (tc.value) {
            .string => |s| try testing.expectEqualStrings(s, retrieved.string),
            .number => |n| try testing.expectEqual(n, retrieved.number),
            .boolean => |b| try testing.expectEqual(b, retrieved.boolean),
            .null => try testing.expectEqual(Value.null, retrieved),
            else => unreachable,
        }
    }
}

test "storage: handles complex nested structures with MessagePack" {
    const allocator = testing.allocator;
    
    // Create temporary test directory
    const test_dir = "test_msgpack_nested";
    try std.fs.cwd().makeDir(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    // Create nested structure
    var user = std.StringHashMap(Value).init(allocator);
    defer user.deinit();
    
    try user.put("name", .{ .string = "Alice" });
    try user.put("age", .{ .number = 30 });
    try user.put("active", .{ .boolean = true });
    
    var address = std.StringHashMap(Value).init(allocator);
    defer address.deinit();
    
    try address.put("street", .{ .string = "123 Main St" });
    try address.put("city", .{ .string = "New York" });
    try address.put("zip", .{ .number = 10001 });
    
    try user.put("address", .{ .object = address });
    
    // Store the user object
    try storage.set("/users/alice", .{ .object = user });
    
    // Retrieve and verify
    var retrieved = try storage.get("/users/alice");
    defer retrieved.deinit(allocator);
    
    try testing.expectEqualStrings("Alice", retrieved.object.get("name").?.string);
    try testing.expectEqual(@as(f64, 30), retrieved.object.get("age").?.number);
    try testing.expectEqual(true, retrieved.object.get("active").?.boolean);
    
    const retrieved_address = retrieved.object.get("address").?.object;
    try testing.expectEqualStrings("123 Main St", retrieved_address.get("street").?.string);
    try testing.expectEqualStrings("New York", retrieved_address.get("city").?.string);
    try testing.expectEqual(@as(f64, 10001), retrieved_address.get("zip").?.number);
}

test "storage: MessagePack provides size reduction over JSON" {
    const allocator = testing.allocator;
    
    // Create a typical user record
    var user = std.StringHashMap(Value).init(allocator);
    defer user.deinit();
    
    try user.put("id", .{ .number = 12345 });
    try user.put("username", .{ .string = "john_doe_2024" });
    try user.put("email", .{ .string = "john.doe@example.com" });
    try user.put("age", .{ .number = 35 });
    try user.put("verified", .{ .boolean = true });
    try user.put("balance", .{ .number = 1234.56 });
    try user.put("last_login", .{ .number = 1704067200 }); // Unix timestamp
    
    const value = Value{ .object = user };
    
    // Compare serialization sizes
    const json = try value.toJson(allocator);
    defer allocator.free(json);
    
    const msgpack = try value.toMsgPack(allocator);
    defer allocator.free(msgpack);
    
    // MessagePack should be smaller
    try testing.expect(msgpack.len < json.len);
    
    // Verify both can be deserialized correctly
    var json_decoded = try Value.fromJson(allocator, json);
    defer json_decoded.deinit(allocator);
    
    var msgpack_decoded = try Value.fromMsgPack(allocator, msgpack);
    defer msgpack_decoded.deinit(allocator);
    
    // Both should have the same data
    try testing.expectEqual(@as(usize, 7), json_decoded.object.count());
    try testing.expectEqual(@as(usize, 7), msgpack_decoded.object.count());
    try testing.expectEqualStrings("john_doe_2024", json_decoded.object.get("username").?.string);
    try testing.expectEqualStrings("john_doe_2024", msgpack_decoded.object.get("username").?.string);
}