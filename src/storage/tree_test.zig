const std = @import("std");
const testing = std.testing;
const tree = @import("tree.zig");

test "Path: init with valid paths" {
    const allocator = testing.allocator;
    
    // Root path
    var root = try tree.Path.init(allocator, "/");
    defer root.deinit();
    try testing.expect(root.isRoot());
    try testing.expectEqual(@as(usize, 0), root.depth());
    
    // Single segment
    var users = try tree.Path.init(allocator, "/users");
    defer users.deinit();
    try testing.expectEqual(@as(usize, 1), users.depth());
    try testing.expectEqualStrings("users", users.segments[0]);
    
    // Multiple segments
    var deep = try tree.Path.init(allocator, "/users/123/posts/456");
    defer deep.deinit();
    try testing.expectEqual(@as(usize, 4), deep.depth());
    try testing.expectEqualStrings("users", deep.segments[0]);
    try testing.expectEqualStrings("123", deep.segments[1]);
    try testing.expectEqualStrings("posts", deep.segments[2]);
    try testing.expectEqualStrings("456", deep.segments[3]);
}

test "Path: init with invalid paths" {
    const allocator = testing.allocator;
    
    // Missing leading slash
    try testing.expectError(error.InvalidPath, tree.Path.init(allocator, "users"));
    
    // Empty path
    try testing.expectError(error.InvalidPath, tree.Path.init(allocator, ""));
    
    // Path too long
    const long_path = "/" ++ ("a" ** 2000);
    try testing.expectError(error.PathTooLong, tree.Path.init(allocator, long_path));
    
    // Empty segments
    try testing.expectError(error.EmptySegment, tree.Path.init(allocator, "/users//posts"));
}

test "Path: parent extraction" {
    const allocator = testing.allocator;
    
    // Root has no parent
    var root = try tree.Path.init(allocator, "/");
    defer root.deinit();
    try testing.expect(root.parent() == null);
    
    // Single segment parent is root
    var users = try tree.Path.init(allocator, "/users");
    defer users.deinit();
    try testing.expectEqualStrings("/", users.parent().?);
    
    // Multiple segments
    var deep = try tree.Path.init(allocator, "/users/123/posts");
    defer deep.deinit();
    try testing.expectEqualStrings("/users/123", deep.parent().?);
}

test "normalizePath: handles various cases" {
    const allocator = testing.allocator;
    
    // Root path unchanged
    const root = try tree.normalizePath(allocator, "/");
    defer allocator.free(root);
    try testing.expectEqualStrings("/", root);
    
    // Remove trailing slash
    const with_slash = try tree.normalizePath(allocator, "/users/");
    defer allocator.free(with_slash);
    try testing.expectEqualStrings("/users", with_slash);
    
    // Already normalized
    const normal = try tree.normalizePath(allocator, "/users/123");
    defer allocator.free(normal);
    try testing.expectEqualStrings("/users/123", normal);
    
    // Invalid paths
    try testing.expectError(error.InvalidPath, tree.normalizePath(allocator, ""));
    try testing.expectError(error.InvalidPath, tree.normalizePath(allocator, "users"));
}

test "pathMatches: wildcard matching" {
    // Exact matches
    try testing.expect(tree.pathMatches("/users", "/users"));
    try testing.expect(tree.pathMatches("/users/123", "/users/123"));
    
    // Wildcard matches
    try testing.expect(tree.pathMatches("/users/123", "/users/*"));
    try testing.expect(tree.pathMatches("/users/123/posts", "/users/*/posts"));
    try testing.expect(tree.pathMatches("/users/123/posts/456", "/users/*/posts/*"));
    
    // Non-matches
    try testing.expect(!tree.pathMatches("/users", "/posts"));
    try testing.expect(!tree.pathMatches("/users/123", "/users/123/posts"));
    try testing.expect(!tree.pathMatches("/users/123/posts", "/users/*"));
}

test "extractVariables: extracts path variables" {
    const allocator = testing.allocator;
    
    // Single variable
    var vars1 = try tree.extractVariables(allocator, "/users/123", "/users/$userId");
    defer vars1.deinit();
    try testing.expectEqualStrings("123", vars1.get("userId").?);
    
    // Multiple variables
    var vars2 = try tree.extractVariables(allocator, "/users/123/posts/456", "/users/$userId/posts/$postId");
    defer vars2.deinit();
    try testing.expectEqualStrings("123", vars2.get("userId").?);
    try testing.expectEqualStrings("456", vars2.get("postId").?);
    
    // Pattern mismatch
    try testing.expectError(
        error.PatternMismatch, 
        tree.extractVariables(allocator, "/users/123", "/posts/$postId")
    );
}

test "Path: memory allocation tracking" {
    // Using testing allocator already ensures no memory leaks
    // Zig 0.14 removed direct access to total_allocated
    const allocator = testing.allocator;
    
    var path = try tree.Path.init(allocator, "/users/123/posts");
    defer path.deinit();
    
    _ = path.parent();
    _ = path.isRoot();
    _ = path.depth();
    
    // Testing allocator will fail if there are leaks
}