const std = @import("std");
const testing = std.testing;
const lmdb = @import("lmdb.zig");

fn setupTestDir(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_cursor_test_{d}", .{timestamp});
    try std.fs.makeDirAbsolute(test_dir);
    return test_dir;
}

fn cleanupTestDir(path: []const u8) void {
    std.fs.deleteTreeAbsolute(path) catch |err| {
        std.log.warn("Failed to cleanup test directory {s}: {}", .{path, err});
    };
}

test "Cursor: basic iteration" {
    const allocator = testing.allocator;
    const test_dir = try setupTestDir(allocator);
    defer allocator.free(test_dir);
    defer cleanupTestDir(test_dir);

    var env = try lmdb.Environment.init(allocator, test_dir);
    defer env.deinit();

    // Write some test data
    {
        var txn = try env.beginTxn(false);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        
        try db.put("/users", "__branch__");
        try db.put("/users/alice", "\"Alice\"");
        try db.put("/users/bob", "\"Bob\"");
        try db.put("/users/charlie", "\"Charlie\"");
        try db.put("/posts", "__branch__");
        try db.put("/posts/1", "\"First post\"");
        
        try txn.commit();
    }

    // Test cursor iteration
    {
        var txn = try env.beginTxn(true);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        var cursor = try db.openCursor();
        defer cursor.deinit();
        
        // Seek to /users and iterate children
        const prefix = "/users/";
        var entry = try cursor.seek(prefix);
        
        var count: usize = 0;
        while (entry) |kv| {
            if (!std.mem.startsWith(u8, kv.key, prefix)) break;
            
            std.debug.print("Found key: {s}, value: {s}\n", .{kv.key, kv.value});
            count += 1;
            
            entry = try cursor.next();
        }
        
        try testing.expectEqual(@as(usize, 3), count); // alice, bob, charlie
    }
}

test "Cursor: seek to specific prefix" {
    const allocator = testing.allocator;
    const test_dir = try setupTestDir(allocator);
    defer allocator.free(test_dir);
    defer cleanupTestDir(test_dir);

    var env = try lmdb.Environment.init(allocator, test_dir);
    defer env.deinit();

    // Write test data
    {
        var txn = try env.beginTxn(false);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        
        try db.put("/a/1", "1");
        try db.put("/a/2", "2");
        try db.put("/b/1", "1");
        try db.put("/b/2", "2");
        
        try txn.commit();
    }

    // Test seeking to /b/
    {
        var txn = try env.beginTxn(true);
        defer txn.deinit();
        
        var db = try txn.openDatabase(null);
        var cursor = try db.openCursor();
        defer cursor.deinit();
        
        const entry = try cursor.seek("/b/");
        
        // First entry should be /b/1
        try testing.expect(entry != null);
        try testing.expectEqualStrings("/b/1", entry.?.key);
        try testing.expectEqualStrings("1", entry.?.value);
    }
}