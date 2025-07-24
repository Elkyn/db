const std = @import("std");
const testing = std.testing;
const RulesParser = @import("parser.zig").RulesParser;

test "RulesParser: parse simple rules" {
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
        \\    },
        \\    "public": {
        \\      ".read": "true",
        \\      ".write": "false"
        \\    }
        \\  }
        \\}
    ;
    
    var config = try parser.parse(json);
    defer config.deinit();
    
    // Check root has children
    try testing.expect(config.root.children.count() == 2);
    
    // Check users rules
    const users = config.root.children.get("users").?;
    try testing.expect(users.children.count() == 1);
    
    const user_var = users.children.get("$userId").?;
    try testing.expect(user_var.read != null);
    try testing.expect(user_var.write != null);
    try testing.expectEqualStrings("$userId === auth.uid", user_var.read.?.expression);
    try testing.expectEqualStrings("$userId === auth.uid", user_var.write.?.expression);
    
    // Check public rules
    const public = config.root.children.get("public").?;
    try testing.expect(public.read != null);
    try testing.expect(public.write != null);
    try testing.expectEqualStrings("true", public.read.?.expression);
    try testing.expectEqualStrings("false", public.write.?.expression);
}

test "RulesParser: parse nested rules" {
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
    
    const users = config.root.children.get("users").?;
    const user_var = users.children.get("$userId").?;
    const profile = user_var.children.get("profile").?;
    
    try testing.expect(profile.read != null);
    try testing.expectEqualStrings("true", profile.read.?.expression);
    
    const email = profile.children.get("email").?;
    try testing.expect(email.read != null);
    try testing.expectEqualStrings("$userId === auth.uid", email.read.?.expression);
}