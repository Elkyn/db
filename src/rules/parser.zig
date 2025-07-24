const std = @import("std");
const Rule = @import("rule.zig").Rule;
const PathRules = @import("rule.zig").PathRules;
const RulesConfig = @import("rule.zig").RulesConfig;
const Value = @import("../storage/value.zig").Value;

const log = std.log.scoped(.rules_parser);

/// Parse rules from JSON
pub const RulesParser = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) RulesParser {
        return .{ .allocator = allocator };
    }
    
    /// Parse rules from JSON string
    pub fn parse(self: *RulesParser, json: []const u8) !RulesConfig {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json, .{});
        defer parsed.deinit();
        
        var config = try RulesConfig.init(self.allocator);
        errdefer config.deinit();
        
        if (parsed.value.object.get("rules")) |rules_value| {
            try self.parseRulesObject(&config.root, rules_value);
        }
        
        return config;
    }
    
    /// Parse a rules object into PathRules
    fn parseRulesObject(self: *RulesParser, parent: *PathRules, value: std.json.Value) !void {
        if (value != .object) return;
        
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            
            if (std.mem.startsWith(u8, key, ".")) {
                // This is a rule type (.read, .write, etc.)
                try self.parseRule(parent, key, val);
            } else {
                // This is a child path
                var child = try PathRules.init(self.allocator, key);
                errdefer child.deinit(self.allocator);
                
                try self.parseRulesObject(&child, val);
                try parent.children.put(key, child);
            }
        }
    }
    
    /// Parse a specific rule
    fn parseRule(self: *RulesParser, rules: *PathRules, rule_type: []const u8, value: std.json.Value) !void {
        if (value != .string) return;
        
        const expression = try self.allocator.dupe(u8, value.string);
        const rule = Rule{ .expression = expression };
        
        if (std.mem.eql(u8, rule_type, ".read")) {
            rules.read = rule;
        } else if (std.mem.eql(u8, rule_type, ".write")) {
            rules.write = rule;
        } else if (std.mem.eql(u8, rule_type, ".validate")) {
            rules.validate = rule;
        }
    }
};