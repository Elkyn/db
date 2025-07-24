const std = @import("std");
const testing = std.testing;
const JWT = @import("jwt.zig").JWT;
const Claims = @import("jwt.zig").Claims;

test "JWT: create and validate token" {
    const allocator = testing.allocator;
    
    var jwt = JWT.init(allocator, "test-secret-key");
    
    // Create claims
    const claims = Claims{
        .uid = "user123",
        .email = "test@example.com",
        .iat = std.time.timestamp(),
        .exp = std.time.timestamp() + 3600, // 1 hour from now
    };
    
    // Create token
    const token = try jwt.create(claims);
    defer allocator.free(token);
    
    // Validate token
    var result = try jwt.validate(token);
    defer result.deinit(allocator);
    
    try testing.expect(result.valid);
    try testing.expectEqualStrings("user123", result.claims.uid.?);
    try testing.expectEqualStrings("test@example.com", result.claims.email.?);
}

test "JWT: invalid signature" {
    const allocator = testing.allocator;
    
    var jwt = JWT.init(allocator, "test-secret-key");
    var jwt_wrong = JWT.init(allocator, "wrong-secret-key");
    
    // Create token with one secret
    const claims = Claims{
        .uid = "user123",
    };
    
    const token = try jwt.create(claims);
    defer allocator.free(token);
    
    // Try to validate with different secret
    var result = try jwt_wrong.validate(token);
    defer result.deinit(allocator);
    
    try testing.expect(!result.valid);
    try testing.expectEqualStrings("Invalid signature", result.error_message.?);
}

test "JWT: expired token" {
    const allocator = testing.allocator;
    
    var jwt = JWT.init(allocator, "test-secret-key");
    
    // Create expired token
    const claims = Claims{
        .uid = "user123",
        .exp = std.time.timestamp() - 3600, // 1 hour ago
    };
    
    const token = try jwt.create(claims);
    defer allocator.free(token);
    
    // Validate token
    var result = try jwt.validate(token);
    defer result.deinit(allocator);
    
    try testing.expect(!result.valid);
    try testing.expectEqualStrings("Token expired", result.error_message.?);
}

test "JWT: malformed token" {
    const allocator = testing.allocator;
    
    var jwt = JWT.init(allocator, "test-secret-key");
    
    // Test various malformed tokens
    try testing.expectError(error.InvalidToken, jwt.validate("not.a.token"));
    try testing.expectError(error.InvalidToken, jwt.validate("only.two"));
    try testing.expectError(error.InvalidToken, jwt.validate("too.many.parts.here"));
}