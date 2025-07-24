const std = @import("std");
const testing = std.testing;
const RulesEngine = @import("engine.zig").RulesEngine;
const AuthContext = @import("../auth/context.zig").AuthContext;
const Storage = @import("../storage/storage.zig").Storage;
const Value = @import("../storage/value.zig").Value;
const test_utils = @import("../test_utils.zig");

test "rules engine: initialization and cleanup" {
    const allocator = testing.allocator;
    
    const test_dir = try test_utils.createTestDir(allocator);
    defer {
        test_utils.cleanupTestDir(test_dir);
        allocator.free(test_dir);
    }
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    var engine = RulesEngine.init(allocator, &storage);
    defer engine.deinit();
    
    try testing.expect(engine.config == null);
}

test "rules engine: load rules from JSON" {
    const allocator = testing.allocator;
    
    const test_dir = try test_utils.createTestDir(allocator);
    defer {
        test_utils.cleanupTestDir(test_dir);
        allocator.free(test_dir);
    }
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    var engine = RulesEngine.init(allocator, &storage);
    defer engine.deinit();
    
    const rules_json =
        \\{
        \\  "rules": {
        \\    "public": {
        \\      ".read": "true",
        \\      ".write": "false"
        \\    }
        \\  }
        \\}
    ;
    
    try engine.loadRules(rules_json);
    try testing.expect(engine.config != null);
}

test "rules engine: deny access when no rules configured" {
    const allocator = testing.allocator;
    
    const test_dir = try test_utils.createTestDir(allocator);
    defer {
        test_utils.cleanupTestDir(test_dir);
        allocator.free(test_dir);
    }
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    var engine = RulesEngine.init(allocator, &storage);
    defer engine.deinit();
    
    const auth = AuthContext{
        .authenticated = true,
        .uid = "user123",
    };
    
    // Without rules, everything should be denied
    const can_read = try engine.canRead("/public/data", &auth);
    try testing.expect(!can_read);
    
    const can_write = try engine.canWrite("/public/data", &auth, null);
    try testing.expect(!can_write);
}

test "rules engine: public read access" {
    const allocator = testing.allocator;
    
    const test_dir = try test_utils.createTestDir(allocator);
    defer {
        test_utils.cleanupTestDir(test_dir);
        allocator.free(test_dir);
    }
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    var engine = RulesEngine.init(allocator, &storage);
    defer engine.deinit();
    
    const rules_json =
        \\{
        \\  "rules": {
        \\    "public": {
        \\      ".read": "true",
        \\      ".write": "false"
        \\    }
        \\  }
        \\}
    ;
    
    try engine.loadRules(rules_json);
    
    // Unauthenticated user
    const unauth = AuthContext{};
    const can_read = try engine.canRead("/public/data", &unauth);
    try testing.expect(can_read);
    
    const can_write = try engine.canWrite("/public/data", &unauth, null);
    try testing.expect(!can_write);
}

test "rules engine: authenticated write access" {
    const allocator = testing.allocator;
    
    const test_dir = try test_utils.createTestDir(allocator);
    defer {
        test_utils.cleanupTestDir(test_dir);
        allocator.free(test_dir);
    }
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    var engine = RulesEngine.init(allocator, &storage);
    defer engine.deinit();
    
    const rules_json =
        \\{
        \\  "rules": {
        \\    "data": {
        \\      ".read": "auth != null",
        \\      ".write": "auth != null"
        \\    }
        \\  }
        \\}
    ;
    
    try engine.loadRules(rules_json);
    
    // Unauthenticated user
    const unauth = AuthContext{};
    var can_read = try engine.canRead("/data/test", &unauth);
    try testing.expect(!can_read);
    
    var can_write = try engine.canWrite("/data/test", &unauth, null);
    try testing.expect(!can_write);
    
    // Authenticated user
    const auth = AuthContext{
        .authenticated = true,
        .uid = "user123",
    };
    can_read = try engine.canRead("/data/test", &auth);
    try testing.expect(can_read);
    
    can_write = try engine.canWrite("/data/test", &auth, null);
    try testing.expect(can_write);
}

test "rules engine: user-specific access control" {
    const allocator = testing.allocator;
    
    const test_dir = try test_utils.createTestDir(allocator);
    defer {
        test_utils.cleanupTestDir(test_dir);
        allocator.free(test_dir);
    }
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    var engine = RulesEngine.init(allocator, &storage);
    defer engine.deinit();
    
    const rules_json =
        \\{
        \\  "rules": {
        \\    "users": {
        \\      "$userId": {
        \\        ".read": "$userId === auth.uid",
        \\        ".write": "$userId === auth.uid"
        \\      }
        \\    }
        \\  }
        \\}
    ;
    
    try engine.loadRules(rules_json);
    
    // User can access their own data
    const user1 = AuthContext{
        .authenticated = true,
        .uid = "user123",
    };
    var can_read = try engine.canRead("/users/user123", &user1);
    try testing.expect(can_read);
    
    var can_write = try engine.canWrite("/users/user123", &user1, null);
    try testing.expect(can_write);
    
    // User cannot access other users' data
    can_read = try engine.canRead("/users/user456", &user1);
    try testing.expect(!can_read);
    
    can_write = try engine.canWrite("/users/user456", &user1, null);
    try testing.expect(!can_write);
}

test "rules engine: with existing data in storage" {
    const allocator = testing.allocator;
    
    const test_dir = try test_utils.createTestDir(allocator);
    defer {
        test_utils.cleanupTestDir(test_dir);
        allocator.free(test_dir);
    }
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    // Add some test data
    const test_value = Value{ .string = try allocator.dupe(u8, "existing data") };
    try storage.set("/test/data", test_value);
    
    var engine = RulesEngine.init(allocator, &storage);
    defer engine.deinit();
    
    const rules_json =
        \\{
        \\  "rules": {
        \\    "test": {
        \\      ".read": "true",
        \\      ".write": "data != null"
        \\    }
        \\  }
        \\}
    ;
    
    try engine.loadRules(rules_json);
    
    const auth = AuthContext{
        .authenticated = true,
        .uid = "user123",
    };
    
    // Can read
    const can_read = try engine.canRead("/test/data", &auth);
    try testing.expect(can_read);
    
    // Can write because data exists
    const can_write = try engine.canWrite("/test/data", &auth, null);
    try testing.expect(can_write);
    
    // Cannot write to non-existent path
    const can_write_new = try engine.canWrite("/test/new", &auth, null);
    try testing.expect(!can_write_new);
}