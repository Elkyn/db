const std = @import("std");
const testing = std.testing;
const rule = @import("rule.zig");

const RuleType = rule.RuleType;
const Rule = rule.Rule;
const PathRules = rule.PathRules;
const RulesConfig = rule.RulesConfig;
const RuleContext = rule.RuleContext;
const Value = @import("../storage/value.zig").Value;

test "rule type: enum values" {
    const read_rule = RuleType.read;
    const write_rule = RuleType.write;
    const validate_rule = RuleType.validate;
    const index_rule = RuleType.index;
    
    try testing.expect(read_rule != write_rule);
    try testing.expect(validate_rule != index_rule);
}

test "rule: creation and cleanup" {
    const allocator = testing.allocator;
    
    var r = Rule{
        .expression = try allocator.dupe(u8, "auth != null"),
        .compiled_fn = null,
    };
    defer r.deinit(allocator);
    
    try testing.expectEqualStrings("auth != null", r.expression);
    try testing.expect(r.compiled_fn == null);
}

test "path rules: initialization" {
    const allocator = testing.allocator;
    
    var path_rules = try PathRules.init(allocator, "/users/$userId");
    defer path_rules.deinit(allocator);
    
    try testing.expectEqualStrings("/users/$userId", path_rules.pattern);
    try testing.expect(path_rules.read == null);
    try testing.expect(path_rules.write == null);
    try testing.expect(path_rules.validate == null);
    try testing.expect(path_rules.index == null);
    try testing.expect(path_rules.children.count() == 0);
}

test "path rules: add rules" {
    const allocator = testing.allocator;
    
    var path_rules = try PathRules.init(allocator, "/users");
    defer path_rules.deinit(allocator);
    
    path_rules.read = Rule{
        .expression = try allocator.dupe(u8, "auth != null"),
    };
    path_rules.write = Rule{
        .expression = try allocator.dupe(u8, "auth.uid === 'admin'"),
    };
    
    try testing.expectEqualStrings("auth != null", path_rules.read.?.expression);
    try testing.expectEqualStrings("auth.uid === 'admin'", path_rules.write.?.expression);
}

test "path rules: add child rules" {
    const allocator = testing.allocator;
    
    var parent = try PathRules.init(allocator, "/");
    defer parent.deinit(allocator);
    
    // Add child rules
    var users_rules = try PathRules.init(allocator, "/users");
    users_rules.read = Rule{ .expression = try allocator.dupe(u8, "true") };
    try parent.children.put(try allocator.dupe(u8, "users"), users_rules);
    
    var posts_rules = try PathRules.init(allocator, "/posts");
    posts_rules.write = Rule{ .expression = try allocator.dupe(u8, "auth != null") };
    try parent.children.put(try allocator.dupe(u8, "posts"), posts_rules);
    
    try testing.expect(parent.children.count() == 2);
    try testing.expect(parent.children.contains("users"));
    try testing.expect(parent.children.contains("posts"));
}

test "rules config: initialization and cleanup" {
    const allocator = testing.allocator;
    
    var config = try RulesConfig.init(allocator);
    defer config.deinit();
    
    try testing.expectEqualStrings("/", config.root.pattern);
    try testing.expect(config.root.read == null);
    try testing.expect(config.root.write == null);
}

test "rule context: initialization" {
    const allocator = testing.allocator;
    
    var ctx = RuleContext.init(allocator);
    defer ctx.deinit();
    
    try testing.expectEqualStrings("", ctx.path);
    try testing.expect(ctx.auth.authenticated == false);
    try testing.expect(ctx.auth.uid == null);
    try testing.expect(ctx.data == null);
    try testing.expect(ctx.new_data == null);
    try testing.expect(ctx.root_accessor == null);
    try testing.expect(ctx.variables.count() == 0);
}

test "rule context: set basic values" {
    const allocator = testing.allocator;
    
    var ctx = RuleContext.init(allocator);
    defer ctx.deinit();
    
    ctx.path = "/users/123";
    ctx.auth = .{
        .authenticated = true,
        .uid = "user123",
        .email = "test@example.com",
    };
    
    try testing.expectEqualStrings("/users/123", ctx.path);
    try testing.expect(ctx.auth.authenticated);
    try testing.expectEqualStrings("user123", ctx.auth.uid.?);
    try testing.expectEqualStrings("test@example.com", ctx.auth.email.?);
}

test "rule context: with data values" {
    const allocator = testing.allocator;
    
    var ctx = RuleContext.init(allocator);
    defer ctx.deinit();
    
    // Set existing data
    ctx.data = Value{ .string = "existing value" };
    
    // Set new data
    ctx.new_data = Value{ .string = "new value" };
    
    try testing.expectEqualStrings("existing value", ctx.data.?.string);
    try testing.expectEqualStrings("new value", ctx.new_data.?.string);
}

test "rule context: with variables" {
    const allocator = testing.allocator;
    
    var ctx = RuleContext.init(allocator);
    defer ctx.deinit();
    
    // Add path variables
    try ctx.variables.put("userId", "user123");
    try ctx.variables.put("postId", "post456");
    
    // Test getting variables
    const user_id = ctx.getVariable("userId");
    try testing.expect(user_id != null);
    try testing.expectEqualStrings("user123", user_id.?);
    
    const post_id = ctx.getVariable("postId");
    try testing.expect(post_id != null);
    try testing.expectEqualStrings("post456", post_id.?);
    
    const missing = ctx.getVariable("missing");
    try testing.expect(missing == null);
}

test "rule context: with root accessor function" {
    const allocator = testing.allocator;
    
    var ctx = RuleContext.init(allocator);
    defer ctx.deinit();
    
    // Mock root accessor
    ctx.root_accessor = struct {
        fn accessor(path: []const u8) ?Value {
            if (std.mem.eql(u8, path, "/config")) {
                return Value{ .string = "config value" };
            }
            return null;
        }
    }.accessor;
    
    // Test accessor
    if (ctx.root_accessor) |accessor| {
        const config_val = accessor("/config");
        try testing.expect(config_val != null);
        try testing.expectEqualStrings("config value", config_val.?.string);
        
        const missing_val = accessor("/missing");
        try testing.expect(missing_val == null);
    }
}

test "path rules: wildcard detection" {
    const allocator = testing.allocator;
    
    var rules = try PathRules.init(allocator, "/users");
    defer rules.deinit(allocator);
    
    // Add a wildcard child
    var wildcard_rules = try PathRules.init(allocator, "/users/$id");
    wildcard_rules.read = Rule{ .expression = try allocator.dupe(u8, "$id === auth.uid") };
    try rules.children.put(try allocator.dupe(u8, "$id"), wildcard_rules);
    
    // Add a regular child
    var regular_rules = try PathRules.init(allocator, "/users/public");
    regular_rules.read = Rule{ .expression = try allocator.dupe(u8, "true") };
    try rules.children.put(try allocator.dupe(u8, "public"), regular_rules);
    
    // Check wildcard detection
    var iter = rules.children.iterator();
    while (iter.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, "$")) {
            try testing.expectEqualStrings("$id", entry.key_ptr.*);
        } else {
            try testing.expectEqualStrings("public", entry.key_ptr.*);
        }
    }
}