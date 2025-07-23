const std = @import("std");
const testing = std.testing;
const storage_mod = @import("storage.zig");
const value_mod = @import("value.zig");

const Storage = storage_mod.Storage;
const Value = value_mod.Value;

fn setupTestStorage(allocator: std.mem.Allocator) !struct { storage: Storage, dir: []const u8 } {
    const nanos = std.time.nanoTimestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_update_test_{d}", .{nanos});
    try std.fs.makeDirAbsolute(test_dir);

    const storage = try Storage.init(allocator, test_dir);
    return .{ .storage = storage, .dir = test_dir };
}

fn cleanupTestDir(path: []const u8) void {
    std.fs.deleteTreeAbsolute(path) catch |err| {
        std.log.warn("Failed to cleanup test directory {s}: {}", .{ path, err });
    };
}

test "Storage update: basic merge" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create initial object
    var initial = std.StringHashMap(Value).init(allocator);
    try initial.put(try allocator.dupe(u8, "name"), Value{ .string = try allocator.dupe(u8, "Alice") });
    try initial.put(try allocator.dupe(u8, "age"), Value{ .number = 30 });
    try initial.put(try allocator.dupe(u8, "city"), Value{ .string = try allocator.dupe(u8, "Boston") });
    
    var initial_value = Value{ .object = initial };
    defer initial_value.deinit(allocator);
    
    try storage.set("/user", initial_value);
    
    // Create update
    var updates = std.StringHashMap(Value).init(allocator);
    try updates.put(try allocator.dupe(u8, "age"), Value{ .number = 31 });
    try updates.put(try allocator.dupe(u8, "city"), Value{ .string = try allocator.dupe(u8, "New York") });
    try updates.put(try allocator.dupe(u8, "job"), Value{ .string = try allocator.dupe(u8, "Engineer") });
    
    var update_value = Value{ .object = updates };
    defer update_value.deinit(allocator);
    
    // Perform update
    try storage.update("/user", update_value);
    
    // Verify result
    var result_value = try storage.get("/user");
    defer result_value.deinit(allocator);
    
    try testing.expect(result_value == .object);
    const obj = result_value.object;
    
    // Check all fields
    try testing.expectEqual(@as(usize, 4), obj.count()); // name, age, city, job
    
    // Original field unchanged
    const name = obj.get("name").?;
    try testing.expect(name == .string);
    try testing.expectEqualStrings("Alice", name.string);
    
    // Updated fields
    const age = obj.get("age").?;
    try testing.expect(age == .number);
    try testing.expectApproxEqRel(31, age.number, 0.001);
    
    const city = obj.get("city").?;
    try testing.expect(city == .string);
    try testing.expectEqualStrings("New York", city.string);
    
    // New field
    const job = obj.get("job").?;
    try testing.expect(job == .string);
    try testing.expectEqualStrings("Engineer", job.string);
}

test "Storage update: create if not exists" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();
    
    // Update non-existent path
    var updates = std.StringHashMap(Value).init(allocator);
    try updates.put(try allocator.dupe(u8, "created"), Value{ .boolean = true });
    
    var update_value = Value{ .object = updates };
    defer update_value.deinit(allocator);
    
    try storage.update("/new", update_value);
    
    // Verify created
    var result_value = try storage.get("/new");
    defer result_value.deinit(allocator);
    
    try testing.expect(result_value == .object);
    const created = result_value.object.get("created").?;
    try testing.expect(created == .boolean);
    try testing.expect(created.boolean == true);
}

test "Storage update: error on non-object" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();
    
    // Set a string value
    try storage.set("/text", Value{ .string = "hello" });
    
    // Try to update it as object
    var updates = std.StringHashMap(Value).init(allocator);
    try updates.put(try allocator.dupe(u8, "field"), Value{ .string = try allocator.dupe(u8, "value") });
    
    var update_value = Value{ .object = updates };
    defer update_value.deinit(allocator);
    
    // Should fail
    try testing.expectError(error.InvalidPath, storage.update("/text", update_value));
}