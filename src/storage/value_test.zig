const std = @import("std");
const testing = std.testing;
const Value = @import("value.zig").Value;

test "value: create and deinit basic types" {
    const allocator = testing.allocator;
    
    // Test null
    var null_value = Value{ .null = {} };
    null_value.deinit(allocator);
    
    // Test boolean
    var bool_value = Value{ .boolean = true };
    bool_value.deinit(allocator);
    
    // Test number
    var num_value = Value{ .number = 42.5 };
    num_value.deinit(allocator);
}

test "value: create and deinit string" {
    const allocator = testing.allocator;
    
    const str = try allocator.dupe(u8, "hello world");
    var string_value = Value{ .string = str };
    string_value.deinit(allocator);
}

test "value: create and deinit object" {
    const allocator = testing.allocator;
    
    var obj = std.StringHashMap(Value).init(allocator);
    try obj.put(try allocator.dupe(u8, "name"), Value{ .string = try allocator.dupe(u8, "Alice") });
    try obj.put(try allocator.dupe(u8, "age"), Value{ .number = 30 });
    
    var object_value = Value{ .object = obj };
    object_value.deinit(allocator);
}

test "value: create and deinit array" {
    const allocator = testing.allocator;
    
    var arr = std.ArrayList(Value).init(allocator);
    try arr.append(Value{ .number = 1 });
    try arr.append(Value{ .string = try allocator.dupe(u8, "test") });
    try arr.append(Value{ .boolean = true });
    
    var array_value = Value{ .array = arr };
    array_value.deinit(allocator);
}

test "value: toJson for basic types" {
    const allocator = testing.allocator;
    
    // Test null
    const null_value = Value{ .null = {} };
    const null_json = try null_value.toJson(allocator);
    defer allocator.free(null_json);
    try testing.expectEqualStrings("null", null_json);
    
    // Test boolean
    const bool_value = Value{ .boolean = true };
    const bool_json = try bool_value.toJson(allocator);
    defer allocator.free(bool_json);
    try testing.expectEqualStrings("true", bool_json);
    
    // Test number
    const num_value = Value{ .number = 42.5 };
    const num_json = try num_value.toJson(allocator);
    defer allocator.free(num_json);
    try testing.expectEqualStrings("42.5", num_json);
    
    // Test string
    const string_value = Value{ .string = "hello \"world\"" };
    const string_json = try string_value.toJson(allocator);
    defer allocator.free(string_json);
    try testing.expectEqualStrings("\"hello \\\"world\\\"\"", string_json);
}

test "value: toJson for complex types" {
    const allocator = testing.allocator;
    
    // Test object
    var obj = std.StringHashMap(Value).init(allocator);
    defer obj.deinit();
    try obj.put("name", Value{ .string = "Alice" });
    try obj.put("age", Value{ .number = 30 });
    
    const object_value = Value{ .object = obj };
    const object_json = try object_value.toJson(allocator);
    defer allocator.free(object_json);
    
    // Object order might vary, so we check it contains expected parts
    try testing.expect(std.mem.indexOf(u8, object_json, "\"name\":\"Alice\"") != null);
    try testing.expect(std.mem.indexOf(u8, object_json, "\"age\":30") != null);
    
    // Test array
    var arr = std.ArrayList(Value).init(allocator);
    defer arr.deinit();
    try arr.append(Value{ .number = 1 });
    try arr.append(Value{ .string = "test" });
    try arr.append(Value{ .boolean = false });
    
    const array_value = Value{ .array = arr };
    const array_json = try array_value.toJson(allocator);
    defer allocator.free(array_json);
    try testing.expectEqualStrings("[1,\"test\",false]", array_json);
}

test "value: fromJson for basic types" {
    const allocator = testing.allocator;
    
    // Test null
    var null_value = try Value.fromJson(allocator, "null");
    defer null_value.deinit(allocator);
    try testing.expect(null_value == .null);
    
    // Test boolean
    var bool_value = try Value.fromJson(allocator, "true");
    defer bool_value.deinit(allocator);
    try testing.expect(bool_value.boolean == true);
    
    // Test number
    var num_value = try Value.fromJson(allocator, "42.5");
    defer num_value.deinit(allocator);
    try testing.expectApproxEqAbs(42.5, num_value.number, 0.001);
    
    // Test string
    var string_value = try Value.fromJson(allocator, "\"hello world\"");
    defer string_value.deinit(allocator);
    try testing.expectEqualStrings("hello world", string_value.string);
}

test "value: fromJson for complex types" {
    const allocator = testing.allocator;
    
    // Test object
    var object_value = try Value.fromJson(allocator, "{\"name\":\"Alice\",\"age\":30}");
    defer object_value.deinit(allocator);
    
    try testing.expect(object_value.object.contains("name"));
    try testing.expect(object_value.object.contains("age"));
    try testing.expectEqualStrings("Alice", object_value.object.get("name").?.string);
    try testing.expectApproxEqAbs(30, object_value.object.get("age").?.number, 0.001);
    
    // Test array
    var array_value = try Value.fromJson(allocator, "[1,\"test\",false]");
    defer array_value.deinit(allocator);
    
    try testing.expect(array_value.array.items.len == 3);
    try testing.expectApproxEqAbs(1, array_value.array.items[0].number, 0.001);
    try testing.expectEqualStrings("test", array_value.array.items[1].string);
    try testing.expect(array_value.array.items[2].boolean == false);
}

test "value: clone basic types" {
    const allocator = testing.allocator;
    
    // Test null
    const null_original = Value{ .null = {} };
    var null_clone = try null_original.clone(allocator);
    defer null_clone.deinit(allocator);
    try testing.expect(null_clone == .null);
    
    // Test boolean
    const bool_original = Value{ .boolean = true };
    var bool_clone = try bool_original.clone(allocator);
    defer bool_clone.deinit(allocator);
    try testing.expect(bool_clone.boolean == true);
    
    // Test number
    const num_original = Value{ .number = 42.5 };
    var num_clone = try num_original.clone(allocator);
    defer num_clone.deinit(allocator);
    try testing.expectApproxEqAbs(42.5, num_clone.number, 0.001);
}

test "value: clone string" {
    const allocator = testing.allocator;
    
    const original = Value{ .string = try allocator.dupe(u8, "hello world") };
    defer {
        var mut = original;
        mut.deinit(allocator);
    }
    
    var clone = try original.clone(allocator);
    defer clone.deinit(allocator);
    
    try testing.expectEqualStrings("hello world", clone.string);
    // Ensure it's a different allocation
    try testing.expect(original.string.ptr != clone.string.ptr);
}

test "value: clone complex types" {
    const allocator = testing.allocator;
    
    // Test object clone
    var original_obj = std.StringHashMap(Value).init(allocator);
    try original_obj.put(try allocator.dupe(u8, "name"), Value{ .string = try allocator.dupe(u8, "Alice") });
    try original_obj.put(try allocator.dupe(u8, "age"), Value{ .number = 30 });
    
    var original_object = Value{ .object = original_obj };
    defer original_object.deinit(allocator);
    
    var object_clone = try original_object.clone(allocator);
    defer object_clone.deinit(allocator);
    
    try testing.expect(object_clone.object.contains("name"));
    try testing.expectEqualStrings("Alice", object_clone.object.get("name").?.string);
    
    // Test array clone
    var original_arr = std.ArrayList(Value).init(allocator);
    try original_arr.append(Value{ .number = 1 });
    try original_arr.append(Value{ .string = try allocator.dupe(u8, "test") });
    
    var original_array = Value{ .array = original_arr };
    defer original_array.deinit(allocator);
    
    var array_clone = try original_array.clone(allocator);
    defer array_clone.deinit(allocator);
    
    try testing.expect(array_clone.array.items.len == 2);
    try testing.expectApproxEqAbs(1, array_clone.array.items[0].number, 0.001);
    try testing.expectEqualStrings("test", array_clone.array.items[1].string);
}

test "value: no allocations for primitive operations" {
    const allocator = testing.allocator;
    
    // Operations on primitives should not allocate
    var null_value = Value{ .null = {} };
    null_value.deinit(allocator);
    
    var bool_value = Value{ .boolean = true };
    bool_value.deinit(allocator);
    
    var num_value = Value{ .number = 42.5 };
    num_value.deinit(allocator);
    
    // Primitives should not allocate or free any memory
}