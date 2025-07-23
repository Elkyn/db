const std = @import("std");
const testing = std.testing;
const storage_mod = @import("storage.zig");
const value_mod = @import("value.zig");

const Storage = storage_mod.Storage;
const Value = value_mod.Value;

fn setupTestStorage(allocator: std.mem.Allocator) !struct { storage: Storage, dir: []const u8 } {
    const timestamp = std.time.timestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_storage_test_{d}", .{timestamp});
    try std.fs.makeDirAbsolute(test_dir);

    const storage = try Storage.init(allocator, test_dir);
    return .{ .storage = storage, .dir = test_dir };
}

fn cleanupTestDir(path: []const u8) void {
    std.fs.deleteTreeAbsolute(path) catch |err| {
        std.log.warn("Failed to cleanup test directory {s}: {}", .{ path, err });
    };
}

test "Storage: basic set and get" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Set string value
    const str_value = Value{ .string = "Hello, World!" };
    try storage.set("/message", str_value);

    // Get value back
    var retrieved = try storage.get("/message");
    defer retrieved.deinit(allocator);

    try testing.expect(retrieved == .string);
    try testing.expectEqualStrings("Hello, World!", retrieved.string);
}

test "Storage: complex object storage" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create a user object
    var user_obj = std.StringHashMap(Value).init(allocator);

    const name_val = Value{ .string = try allocator.dupe(u8, "Alice") };
    const age_val = Value{ .number = 30 };
    const active_val = Value{ .boolean = true };

    try user_obj.put(try allocator.dupe(u8, "name"), name_val);
    try user_obj.put(try allocator.dupe(u8, "age"), age_val);
    try user_obj.put(try allocator.dupe(u8, "active"), active_val);

    var user_value = Value{ .object = user_obj };
    defer user_value.deinit(allocator);

    try storage.set("/users/alice", user_value);

    // Retrieve and verify
    var retrieved = try storage.get("/users/alice");
    defer retrieved.deinit(allocator);

    try testing.expect(retrieved == .object);
    // Note: Deep object comparison would require more implementation
}

test "Storage: array values" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create an array
    var tags = std.ArrayList(Value).init(allocator);

    try tags.append(Value{ .string = try allocator.dupe(u8, "zig") });
    try tags.append(Value{ .string = try allocator.dupe(u8, "database") });
    try tags.append(Value{ .string = try allocator.dupe(u8, "fast") });

    var tags_value = Value{ .array = tags };
    defer tags_value.deinit(allocator);

    try storage.set("/project/tags", tags_value);

    // Retrieve
    var retrieved = try storage.get("/project/tags");
    defer retrieved.deinit(allocator);

    try testing.expect(retrieved == .array);
    try testing.expectEqual(@as(usize, 3), retrieved.array.items.len);
}

test "Storage: numeric values" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Store different numeric values
    try storage.set("/stats/score", Value{ .number = 95.5 });
    try storage.set("/stats/count", Value{ .number = 42 });

    // Retrieve and verify
    var score = try storage.get("/stats/score");
    defer score.deinit(allocator);
    try testing.expect(score == .number);
    try testing.expectApproxEqRel(95.5, score.number, 0.001);

    var count = try storage.get("/stats/count");
    defer count.deinit(allocator);
    try testing.expect(count == .number);
    try testing.expectApproxEqRel(42, count.number, 0.001);
}

test "Storage: boolean and null values" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Boolean values
    try storage.set("/settings/enabled", Value{ .boolean = true });
    try storage.set("/settings/debug", Value{ .boolean = false });

    // Null value
    try storage.set("/settings/optional", Value{ .null = {} });

    // Retrieve and verify
    var enabled = try storage.get("/settings/enabled");
    defer enabled.deinit(allocator);
    try testing.expect(enabled == .boolean);
    try testing.expect(enabled.boolean == true);

    var debug = try storage.get("/settings/debug");
    defer debug.deinit(allocator);
    try testing.expect(debug == .boolean);
    try testing.expect(debug.boolean == false);

    var optional = try storage.get("/settings/optional");
    defer optional.deinit(allocator);
    try testing.expect(optional == .null);
}

test "Storage: delete operation" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Set a value
    try storage.set("/temp/data", Value{ .string = "temporary" });

    // Verify it exists
    try testing.expect(storage.exists("/temp/data"));

    // Delete it
    try storage.delete("/temp/data");

    // Verify it's gone
    try testing.expect(!storage.exists("/temp/data"));
    try testing.expectError(error.NotFound, storage.get("/temp/data"));
}

test "Storage: path normalization" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Set with trailing slash
    try storage.set("/users/", Value{ .string = "test" });

    // Get without trailing slash (should work due to normalization)
    var retrieved = try storage.get("/users");
    defer retrieved.deinit(allocator);

    try testing.expect(retrieved == .string);
    try testing.expectEqualStrings("test", retrieved.string);
}

test "Storage: deep paths" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Set values at different depths
    try storage.set("/a", Value{ .number = 1 });
    try storage.set("/a/b", Value{ .number = 2 });
    try storage.set("/a/b/c", Value{ .number = 3 });
    try storage.set("/a/b/c/d/e/f", Value{ .number = 6 });

    // Verify all exist independently
    try testing.expect(storage.exists("/a"));
    try testing.expect(storage.exists("/a/b"));
    try testing.expect(storage.exists("/a/b/c"));
    try testing.expect(storage.exists("/a/b/c/d/e/f"));
}

test "Storage: overwrite existing values" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Set initial value
    try storage.set("/config/version", Value{ .number = 1 });

    // Overwrite with new value
    try storage.set("/config/version", Value{ .number = 2 });

    // Verify new value
    var version = try storage.get("/config/version");
    defer version.deinit(allocator);
    try testing.expect(version == .number);
    try testing.expectApproxEqRel(2, version.number, 0.001);
}

test "Storage: update operation" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Set initial object
    var profile = std.StringHashMap(Value).init(allocator);
    try profile.put(try allocator.dupe(u8, "status"), Value{ .string = try allocator.dupe(u8, "initial") });
    try profile.put(try allocator.dupe(u8, "level"), Value{ .number = 1 });
    
    var profile_value = Value{ .object = profile };
    defer profile_value.deinit(allocator);
    
    try storage.set("/user/profile", profile_value);

    // Update with partial data
    var updates = std.StringHashMap(Value).init(allocator);
    try updates.put(try allocator.dupe(u8, "status"), Value{ .string = try allocator.dupe(u8, "updated") });
    try updates.put(try allocator.dupe(u8, "score"), Value{ .number = 100 });
    
    var update_value = Value{ .object = updates };
    defer update_value.deinit(allocator);
    
    try storage.update("/user/profile", update_value);

    // Verify merge
    var result_profile = try storage.get("/user/profile");
    defer result_profile.deinit(allocator);
    
    try testing.expect(result_profile == .object);
    try testing.expectEqual(@as(usize, 3), result_profile.object.count()); // status, level, score
    
    const status = result_profile.object.get("status").?;
    try testing.expectEqualStrings("updated", status.string);
    
    const level = result_profile.object.get("level").?;
    try testing.expectApproxEqRel(1, level.number, 0.001);
    
    const score = result_profile.object.get("score").?;
    try testing.expectApproxEqRel(100, score.number, 0.001);

    // Update non-existent path should create it
    var new_obj = std.StringHashMap(Value).init(allocator);
    try new_obj.put(try allocator.dupe(u8, "created"), Value{ .boolean = true });
    
    var new_value = Value{ .object = new_obj };
    defer new_value.deinit(allocator);
    
    try storage.update("/user/new", new_value);
    try testing.expect(storage.exists("/user/new"));
}

test "Storage: simple tree expansion" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create simple nested object
    var user = std.StringHashMap(Value).init(allocator);
    try user.put(try allocator.dupe(u8, "name"), Value{ .string = try allocator.dupe(u8, "Alice") });
    try user.put(try allocator.dupe(u8, "age"), Value{ .number = 30 });

    var user_value = Value{ .object = user };
    defer user_value.deinit(allocator);

    // Set at /user path
    try storage.set("/user", user_value);

    // Now we should be able to access nested paths
    var name = try storage.get("/user/name");
    defer name.deinit(allocator);
    try testing.expect(name == .string);
    try testing.expectEqualStrings("Alice", name.string);

    var age = try storage.get("/user/age");
    defer age.deinit(allocator);
    try testing.expect(age == .number);
    try testing.expectApproxEqRel(30, age.number, 0.001);

    // Test reading the branch node
    var user_read = try storage.get("/user");
    defer user_read.deinit(allocator);
    try testing.expect(user_read == .object);
    try testing.expectEqual(@as(usize, 2), user_read.object.count());

    // Verify the reconstructed object has the correct values
    const name_val = user_read.object.get("name");
    try testing.expect(name_val != null);
    try testing.expect(name_val.? == .string);

    const age_val = user_read.object.get("age");
    try testing.expect(age_val != null);
    try testing.expect(age_val.? == .number);
}

test "Storage: recursive delete operation" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create nested structure
    var posts = std.StringHashMap(Value).init(allocator);
    try posts.put(try allocator.dupe(u8, "title"), Value{ .string = try allocator.dupe(u8, "My Post") });
    try posts.put(try allocator.dupe(u8, "content"), Value{ .string = try allocator.dupe(u8, "Hello World") });
    
    var profile = std.StringHashMap(Value).init(allocator);
    try profile.put(try allocator.dupe(u8, "name"), Value{ .string = try allocator.dupe(u8, "Alice") });
    try profile.put(try allocator.dupe(u8, "posts"), Value{ .object = posts });
    
    var user_value = Value{ .object = profile };
    defer user_value.deinit(allocator);
    
    try storage.set("/users/alice", user_value);
    
    // Also create another user to ensure /users becomes a branch
    const bob_str = try allocator.dupe(u8, "Bob");
    defer allocator.free(bob_str);
    try storage.set("/users/bob", Value{ .string = bob_str });
    
    // Verify all paths exist
    try testing.expect(storage.exists("/users"));
    try testing.expect(storage.exists("/users/alice"));
    try testing.expect(storage.exists("/users/bob"));
    try testing.expect(storage.exists("/users/alice/name"));
    try testing.expect(storage.exists("/users/alice/posts"));
    try testing.expect(storage.exists("/users/alice/posts/title"));
    try testing.expect(storage.exists("/users/alice/posts/content"));
    
    // Delete the user - should delete all children
    try storage.delete("/users/alice");
    
    // Verify all children are gone
    try testing.expect(!storage.exists("/users/alice"));
    try testing.expect(!storage.exists("/users/alice/name"));
    try testing.expect(!storage.exists("/users/alice/posts"));
    try testing.expect(!storage.exists("/users/alice/posts/title"));
    try testing.expect(!storage.exists("/users/alice/posts/content"));
    
    // But /users and /users/bob should still exist
    try testing.expect(storage.exists("/users"));
    try testing.expect(storage.exists("/users/bob"));
}

test "Storage: delete entire tree from root" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create some data
    const alice = try allocator.dupe(u8, "Alice");
    defer allocator.free(alice);
    const bob = try allocator.dupe(u8, "Bob");
    defer allocator.free(bob);
    const post1 = try allocator.dupe(u8, "Post 1");
    defer allocator.free(post1);
    const post2 = try allocator.dupe(u8, "Post 2");
    defer allocator.free(post2);
    
    try storage.set("/users/alice", Value{ .string = alice });
    try storage.set("/users/bob", Value{ .string = bob });
    try storage.set("/posts/1", Value{ .string = post1 });
    try storage.set("/posts/2", Value{ .string = post2 });
    
    // Delete everything from root
    try storage.delete("/");
    
    // Verify everything is gone
    try testing.expect(!storage.exists("/users"));
    try testing.expect(!storage.exists("/users/alice"));
    try testing.expect(!storage.exists("/users/bob"));
    try testing.expect(!storage.exists("/posts"));
    try testing.expect(!storage.exists("/posts/1"));
    try testing.expect(!storage.exists("/posts/2"));
    
    // Root should still exist (as empty)
    try testing.expect(storage.exists("/"));
}

test "Storage: tree expansion for nested objects REAL" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create nested object structure
    var inner = std.StringHashMap(Value).init(allocator);
    try inner.put(try allocator.dupe(u8, "alfred"), Value{ .string = try allocator.dupe(u8, "Hello") });

    var middle = std.StringHashMap(Value).init(allocator);
    try middle.put(try allocator.dupe(u8, "tata"), Value{ .object = inner });

    var root = std.StringHashMap(Value).init(allocator);
    try root.put(try allocator.dupe(u8, "toto"), Value{ .object = middle });
    try root.put(try allocator.dupe(u8, "jean"), Value{ .string = try allocator.dupe(u8, "Yeah") });

    var root_value = Value{ .object = root };
    defer root_value.deinit(allocator);

    // Set at root
    try storage.set("/", root_value);

    // Now we should be able to access nested paths directly
    var alfred = try storage.get("/toto/tata/alfred");
    defer alfred.deinit(allocator);
    try testing.expect(alfred == .string);
    try testing.expectEqualStrings("Hello", alfred.string);

    var jean = try storage.get("/jean");
    defer jean.deinit(allocator);
    try testing.expect(jean == .string);
    try testing.expectEqualStrings("Yeah", jean.string);

    // Branch nodes should exist
    try testing.expect(storage.exists("/toto"));
    try testing.expect(storage.exists("/toto/tata"));

    // Test reading branch nodes
    var toto = try storage.get("/toto");
    defer toto.deinit(allocator);
    try testing.expect(toto == .object);
    try testing.expectEqual(@as(usize, 1), toto.object.count());

    // The toto object should contain tata
    const tata_val = toto.object.get("tata");
    try testing.expect(tata_val != null);
    try testing.expect(tata_val.? == .object);

    // Test reading root
    var root_read = try storage.get("/");
    defer root_read.deinit(allocator);
    try testing.expect(root_read == .object);
    try testing.expectEqual(@as(usize, 2), root_read.object.count());

    // Root should have both toto and jean
    const root_toto = root_read.object.get("toto");
    try testing.expect(root_toto != null);
    try testing.expect(root_toto.? == .object);

    const root_jean = root_read.object.get("jean");
    try testing.expect(root_jean != null);
    try testing.expect(root_jean.? == .string);
}
