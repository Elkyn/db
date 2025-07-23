const std = @import("std");
const testing = std.testing;
const lmdb = @import("lmdb.zig");

fn setupTestDir(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_test_{d}", .{timestamp});
    try std.fs.makeDirAbsolute(test_dir);
    return test_dir;
}

fn cleanupTestDir(path: []const u8) void {
    std.fs.deleteTreeAbsolute(path) catch |err| {
        std.log.warn("Failed to cleanup test directory {s}: {}", .{path, err});
    };
}

test "Environment: init and deinit" {
    const allocator = testing.allocator;
    const test_dir = try setupTestDir(allocator);
    defer allocator.free(test_dir);
    defer cleanupTestDir(test_dir);

    var env = try lmdb.Environment.init(allocator, test_dir);
    defer env.deinit();
    
    // Environment should be initialized
    try testing.expect(env.env != null);
}

test "Transaction: read-write operations" {
    const allocator = testing.allocator;
    const test_dir = try setupTestDir(allocator);
    defer allocator.free(test_dir);
    defer cleanupTestDir(test_dir);

    var env = try lmdb.Environment.init(allocator, test_dir);
    defer env.deinit();

    // Write transaction
    {
        var txn = try env.beginTxn(false);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        
        try db.put("key1", "value1");
        try db.put("key2", "value2");
        
        try txn.commit();
    }

    // Read transaction
    {
        var txn = try env.beginTxn(true);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        
        const val1 = try db.get("key1");
        try testing.expectEqualStrings("value1", val1);
        
        const val2 = try db.get("key2");
        try testing.expectEqualStrings("value2", val2);
    }
}

test "Database: CRUD operations" {
    const allocator = testing.allocator;
    const test_dir = try setupTestDir(allocator);
    defer allocator.free(test_dir);
    defer cleanupTestDir(test_dir);

    var env = try lmdb.Environment.init(allocator, test_dir);
    defer env.deinit();

    // Create
    {
        var txn = try env.beginTxn(false);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        try db.put("test_key", "test_value");
        
        try txn.commit();
    }

    // Read
    {
        var txn = try env.beginTxn(true);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        const value = try db.get("test_key");
        try testing.expectEqualStrings("test_value", value);
    }

    // Update
    {
        var txn = try env.beginTxn(false);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        try db.put("test_key", "updated_value");
        
        try txn.commit();
    }

    // Verify update
    {
        var txn = try env.beginTxn(true);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        const value = try db.get("test_key");
        try testing.expectEqualStrings("updated_value", value);
    }

    // Delete
    {
        var txn = try env.beginTxn(false);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        try db.delete("test_key");
        
        try txn.commit();
    }

    // Verify deletion
    {
        var txn = try env.beginTxn(true);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        const result = db.get("test_key");
        try testing.expectError(error.NotFound, result);
    }
}

test "Database: handles missing keys" {
    const allocator = testing.allocator;
    const test_dir = try setupTestDir(allocator);
    defer allocator.free(test_dir);
    defer cleanupTestDir(test_dir);

    var env = try lmdb.Environment.init(allocator, test_dir);
    defer env.deinit();

    var txn = try env.beginTxn(true);
    defer txn.deinit();
    
    var db = try txn.openDatabase(null);
    
    // Get non-existent key
    const result = db.get("non_existent");
    try testing.expectError(error.NotFound, result);
}

test "Transaction: rollback on abort" {
    const allocator = testing.allocator;
    const test_dir = try setupTestDir(allocator);
    defer allocator.free(test_dir);
    defer cleanupTestDir(test_dir);

    var env = try lmdb.Environment.init(allocator, test_dir);
    defer env.deinit();

    // Write without commit (implicit abort)
    {
        var txn = try env.beginTxn(false);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        try db.put("rollback_test", "should_not_exist");
        
        // Transaction aborted by deinit without commit
    }

    // Verify data was not persisted
    {
        var txn = try env.beginTxn(true);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        const result = db.get("rollback_test");
        try testing.expectError(error.NotFound, result);
    }
}

test "Database: binary data support" {
    const allocator = testing.allocator;
    const test_dir = try setupTestDir(allocator);
    defer allocator.free(test_dir);
    defer cleanupTestDir(test_dir);

    var env = try lmdb.Environment.init(allocator, test_dir);
    defer env.deinit();

    const binary_data = [_]u8{ 0x00, 0xFF, 0x42, 0x13, 0x37 };

    // Write binary data
    {
        var txn = try env.beginTxn(false);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        try db.put("binary_key", &binary_data);
        
        try txn.commit();
    }

    // Read and verify binary data
    {
        var txn = try env.beginTxn(true);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        const value = try db.get("binary_key");
        try testing.expectEqualSlices(u8, &binary_data, value);
    }
}