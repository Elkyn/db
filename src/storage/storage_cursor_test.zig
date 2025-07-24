const std = @import("std");
const testing = std.testing;
const Storage = @import("storage.zig").Storage;
const Value = @import("value.zig").Value;

test "storage: cursor optimization for large datasets" {
    const allocator = testing.allocator;
    
    // Create temporary directory for database
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    // Create a large dataset with many paths
    // Structure:
    // /users/1 through /users/1000
    // /products/1 through /products/1000
    // /orders/1 through /orders/1000
    
    var timer = try std.time.Timer.start();
    
    // Insert test data
    for (0..1000) |i| {
        const user_path = try std.fmt.allocPrint(allocator, "/users/{d}", .{i});
        defer allocator.free(user_path);
        var user_value = Value{ .string = try std.fmt.allocPrint(allocator, "User {d}", .{i}) };
        defer user_value.deinit(allocator);
        try storage.set(user_path, user_value);
        
        const product_path = try std.fmt.allocPrint(allocator, "/products/{d}", .{i});
        defer allocator.free(product_path);
        var product_value = Value{ .string = try std.fmt.allocPrint(allocator, "Product {d}", .{i}) };
        defer product_value.deinit(allocator);
        try storage.set(product_path, product_value);
        
        const order_path = try std.fmt.allocPrint(allocator, "/orders/{d}", .{i});
        defer allocator.free(order_path);
        var order_value = Value{ .string = try std.fmt.allocPrint(allocator, "Order {d}", .{i}) };
        defer order_value.deinit(allocator);
        try storage.set(order_path, order_value);
    }
    
    const insert_time = timer.read();
    std.log.info("Inserted 3000 items in {d}ms", .{insert_time / std.time.ns_per_ms});
    
    // Test 1: Get /users object (should only scan users, not products/orders)
    timer.reset();
    var users_obj = try storage.get("/users");
    defer users_obj.deinit(allocator);
    const users_time = timer.read();
    
    try testing.expect(users_obj == .object);
    try testing.expectEqual(@as(usize, 1000), users_obj.object.count());
    std.log.info("Retrieved /users object with 1000 children in {d}ms", .{users_time / std.time.ns_per_ms});
    
    // Test 2: Get /products object
    timer.reset();
    var products_obj = try storage.get("/products");
    defer products_obj.deinit(allocator);
    const products_time = timer.read();
    
    try testing.expect(products_obj == .object);
    try testing.expectEqual(@as(usize, 1000), products_obj.object.count());
    std.log.info("Retrieved /products object with 1000 children in {d}ms", .{products_time / std.time.ns_per_ms});
    
    // Test 3: Get root object (should efficiently handle all 3 categories)
    timer.reset();
    var root_obj = try storage.get("/");
    defer root_obj.deinit(allocator);
    const root_time = timer.read();
    
    try testing.expect(root_obj == .object);
    try testing.expectEqual(@as(usize, 3), root_obj.object.count()); // users, products, orders
    std.log.info("Retrieved root object with 3 children in {d}ms", .{root_time / std.time.ns_per_ms});
    
    // Note: We log the times for manual performance analysis, but don't assert on them
    // because timing tests are inherently flaky in unit tests
}

test "storage: cursor seek optimization with deep nesting" {
    const allocator = testing.allocator;
    
    // Create temporary directory for database
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const data_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_path);
    
    var storage = try Storage.init(allocator, data_path);
    defer storage.deinit();
    
    // Create deeply nested structure
    // /a/b/c/d/e/f/g/h/i/j/value with many siblings at each level
    const levels = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" };
    
    // Create siblings at each level
    for (levels, 0..) |_, depth| {
        var path_buf: [256]u8 = undefined;
        var path_len: usize = 1;
        path_buf[0] = '/';
        
        // Build path up to current depth
        for (0..depth + 1) |i| {
            const part = levels[i];
            @memcpy(path_buf[path_len..path_len + part.len], part);
            path_len += part.len;
            if (i < depth) {
                path_buf[path_len] = '/';
                path_len += 1;
            }
        }
        
        const base_path = path_buf[0..path_len];
        
        // Add siblings
        for (0..10) |sibling| {
            const sibling_path = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ base_path, sibling });
            defer allocator.free(sibling_path);
            
            var value = Value{ .string = try std.fmt.allocPrint(allocator, "Value at {s}", .{sibling_path}) };
            defer value.deinit(allocator);
            try storage.set(sibling_path, value);
        }
    }
    
    // Now test retrieval at various depths
    var timer = try std.time.Timer.start();
    
    // Get /a should only retrieve immediate children, not scan all nested data
    var a_obj = try storage.get("/a");
    defer a_obj.deinit(allocator);
    const a_time = timer.read();
    
    try testing.expect(a_obj == .object);
    try testing.expectEqual(@as(usize, 11), a_obj.object.count()); // 'b' + 10 siblings
    std.log.info("Retrieved /a object in {d}μs", .{a_time / std.time.ns_per_us});
    
    // Log the time for manual analysis but don't assert on it
    std.log.info("Deep nesting test completed in {d}μs", .{a_time / std.time.ns_per_us});
}