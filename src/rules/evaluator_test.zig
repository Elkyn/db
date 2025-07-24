const std = @import("std");
const testing = std.testing;
const RulesParser = @import("parser.zig").RulesParser;
const RuleEvaluator = @import("evaluator.zig").RuleEvaluator;
const RuleContext = @import("rule.zig").RuleContext;
const RuleType = @import("rule.zig").RuleType;

test "RuleEvaluator: simple true/false rules" {
    const allocator = testing.allocator;
    
    var parser = RulesParser.init(allocator);
    const json =
        \\{
        \\  "rules": {
        \\    "public": {
        \\      ".read": "true",
        \\      ".write": "false"
        \\    }
        \\  }
        \\}
    ;
    
    var config = try parser.parse(json);
    defer config.deinit();
    
    var evaluator = RuleEvaluator.init(allocator);
    var context = RuleContext.init(allocator);
    defer context.deinit();
    
    context.path = "/public";
    
    // Read should be allowed
    try testing.expect(try evaluator.evaluate(&config, .read, &context));
    
    // Write should be denied
    try testing.expect(!try evaluator.evaluate(&config, .write, &context));
}

test "RuleEvaluator: auth-based rules" {
    const allocator = testing.allocator;
    
    var parser = RulesParser.init(allocator);
    const json =
        \\{
        \\  "rules": {
        \\    "private": {
        \\      ".read": "auth != null",
        \\      ".write": "auth.uid != null"
        \\    }
        \\  }
        \\}
    ;
    
    var config = try parser.parse(json);
    defer config.deinit();
    
    var evaluator = RuleEvaluator.init(allocator);
    var context = RuleContext.init(allocator);
    defer context.deinit();
    
    context.path = "/private";
    
    // Without auth, both should be denied
    try testing.expect(!try evaluator.evaluate(&config, .read, &context));
    try testing.expect(!try evaluator.evaluate(&config, .write, &context));
    
    // With auth but no uid, read allowed but write denied
    context.auth.authenticated = true;
    try testing.expect(try evaluator.evaluate(&config, .read, &context));
    try testing.expect(!try evaluator.evaluate(&config, .write, &context));
    
    // With auth and uid, both allowed
    context.auth.uid = "user123";
    try testing.expect(try evaluator.evaluate(&config, .read, &context));
    try testing.expect(try evaluator.evaluate(&config, .write, &context));
}

test "RuleEvaluator: variable substitution" {
    const allocator = testing.allocator;
    
    var parser = RulesParser.init(allocator);
    const json =
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
    
    var config = try parser.parse(json);
    defer config.deinit();
    
    var evaluator = RuleEvaluator.init(allocator);
    var context = RuleContext.init(allocator);
    defer context.deinit();
    
    context.path = "/users/user123";
    context.auth.authenticated = true;
    context.auth.uid = "user123";
    
    // Should be allowed when uid matches
    try testing.expect(try evaluator.evaluate(&config, .read, &context));
    try testing.expect(try evaluator.evaluate(&config, .write, &context));
    
    // Should be denied when uid doesn't match
    context.auth.uid = "different-user";
    try testing.expect(!try evaluator.evaluate(&config, .read, &context));
    try testing.expect(!try evaluator.evaluate(&config, .write, &context));
}

test "RuleEvaluator: nested path rules" {
    const allocator = testing.allocator;
    
    var parser = RulesParser.init(allocator);
    const json =
        \\{
        \\  "rules": {
        \\    "users": {
        \\      "$userId": {
        \\        ".read": "$userId === auth.uid",
        \\        "profile": {
        \\          ".read": "true",
        \\          "email": {
        \\            ".read": "$userId === auth.uid"
        \\          }
        \\        }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    
    var config = try parser.parse(json);
    defer config.deinit();
    
    var evaluator = RuleEvaluator.init(allocator);
    var context = RuleContext.init(allocator);
    defer context.deinit();
    
    context.auth.authenticated = true;
    context.auth.uid = "user123";
    
    // Profile should be readable by anyone
    context.path = "/users/user456/profile";
    try testing.expect(try evaluator.evaluate(&config, .read, &context));
    
    // Email should only be readable by the user
    context.path = "/users/user456/profile/email";
    try testing.expect(!try evaluator.evaluate(&config, .read, &context));
    
    context.path = "/users/user123/profile/email";
    try testing.expect(try evaluator.evaluate(&config, .read, &context));
}