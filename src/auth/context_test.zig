const std = @import("std");
const testing = std.testing;
const AuthContext = @import("context.zig").AuthContext;

test "auth context: default initialization" {
    const ctx = AuthContext{};
    
    try testing.expect(ctx.authenticated == false);
    try testing.expect(ctx.uid == null);
    try testing.expect(ctx.email == null);
    try testing.expect(ctx.roles.len == 0);
    try testing.expect(ctx.exp == null);
    try testing.expect(ctx.token == null);
}

test "auth context: isAuthenticated checks" {
    // Not authenticated by default
    var ctx = AuthContext{};
    try testing.expect(!ctx.isAuthenticated());
    
    // Setting authenticated alone is not enough
    ctx.authenticated = true;
    try testing.expect(!ctx.isAuthenticated());
    
    // Need both authenticated and uid
    ctx.uid = "user123";
    try testing.expect(ctx.isAuthenticated());
    
    // If authenticated is false, should return false even with uid
    ctx.authenticated = false;
    try testing.expect(!ctx.isAuthenticated());
}

test "auth context: hasRole checks" {
    const ctx = AuthContext{
        .authenticated = true,
        .uid = "user123",
        .roles = &[_][]const u8{ "user", "editor" },
    };
    
    try testing.expect(ctx.hasRole("user"));
    try testing.expect(ctx.hasRole("editor"));
    try testing.expect(!ctx.hasRole("admin"));
    try testing.expect(!ctx.hasRole(""));
    try testing.expect(!ctx.hasRole("unknown"));
}

test "auth context: isAdmin checks" {
    // No admin role
    var ctx = AuthContext{
        .authenticated = true,
        .uid = "user123",
        .roles = &[_][]const u8{ "user", "editor" },
    };
    try testing.expect(!ctx.isAdmin());
    
    // With admin role
    ctx.roles = &[_][]const u8{ "user", "admin" };
    try testing.expect(ctx.isAdmin());
}

test "auth context: deinit frees allocated memory" {
    const allocator = testing.allocator;
    
    var ctx = AuthContext{
        .authenticated = true,
        .uid = try allocator.dupe(u8, "user123"),
        .email = try allocator.dupe(u8, "user@example.com"),
        .token = try allocator.dupe(u8, "eyJhbGc..."),
        .exp = 1234567890,
    };
    
    ctx.deinit(allocator);
}

test "auth context: full context creation" {
    const allocator = testing.allocator;
    
    var ctx = AuthContext{
        .authenticated = true,
        .uid = try allocator.dupe(u8, "user123"),
        .email = try allocator.dupe(u8, "user@example.com"),
        .roles = &[_][]const u8{ "user", "editor", "viewer" },
        .exp = 1234567890,
        .token = try allocator.dupe(u8, "eyJhbGc..."),
    };
    defer ctx.deinit(allocator);
    
    try testing.expect(ctx.isAuthenticated());
    try testing.expectEqualStrings("user123", ctx.uid.?);
    try testing.expectEqualStrings("user@example.com", ctx.email.?);
    try testing.expect(ctx.hasRole("user"));
    try testing.expect(ctx.hasRole("editor"));
    try testing.expect(ctx.hasRole("viewer"));
    try testing.expect(!ctx.hasRole("admin"));
    try testing.expectEqual(@as(i64, 1234567890), ctx.exp.?);
    try testing.expectEqualStrings("eyJhbGc...", ctx.token.?);
}

test "auth context: partial context with null fields" {
    const allocator = testing.allocator;
    
    var ctx = AuthContext{
        .authenticated = true,
        .uid = try allocator.dupe(u8, "user123"),
        .email = null,
        .roles = &[_][]const u8{},
        .exp = null,
        .token = null,
    };
    defer ctx.deinit(allocator);
    
    try testing.expect(ctx.isAuthenticated());
    try testing.expectEqualStrings("user123", ctx.uid.?);
    try testing.expect(ctx.email == null);
    try testing.expect(ctx.roles.len == 0);
    try testing.expect(!ctx.hasRole("user"));
    try testing.expect(!ctx.isAdmin());
}