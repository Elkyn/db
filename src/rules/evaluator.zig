const std = @import("std");
const Rule = @import("rule.zig").Rule;
const RuleContext = @import("rule.zig").RuleContext;
const PathRules = @import("rule.zig").PathRules;
const RulesConfig = @import("rule.zig").RulesConfig;
const RuleType = @import("rule.zig").RuleType;

const log = std.log.scoped(.rules_eval);

/// Rule evaluation engine
pub const RuleEvaluator = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) RuleEvaluator {
        return .{ .allocator = allocator };
    }
    
    /// Evaluate if an operation is allowed
    pub fn evaluate(self: *RuleEvaluator, config: *const RulesConfig, rule_type: RuleType, context: *RuleContext) !bool {
        // Split the path into segments
        var segments = std.ArrayList([]const u8).init(self.allocator);
        defer segments.deinit();
        
        var iter = std.mem.tokenizeScalar(u8, context.path, '/');
        while (iter.next()) |segment| {
            try segments.append(segment);
        }
        
        // Start from root and traverse down
        return try self.evaluatePath(&config.root, rule_type, context, segments.items, 0);
    }
    
    /// Recursively evaluate rules along the path
    fn evaluatePath(
        self: *RuleEvaluator,
        rules: *const PathRules,
        rule_type: RuleType,
        context: *RuleContext,
        segments: []const []const u8,
        depth: usize,
    ) !bool {
        // Get the rule for this level
        const rule = switch (rule_type) {
            .read => rules.read,
            .write => rules.write,
            .validate => rules.validate,
            .index => null, // TODO: implement index rules
        };
        
        // If we're at the target depth, evaluate the rule
        if (depth == segments.len) {
            if (rule) |r| {
                return try self.evaluateExpression(r.expression, context);
            }
            // No rule means deny by default
            return false;
        }
        
        // Otherwise, traverse to the next level
        const segment = segments[depth];
        
        // First check for exact match
        if (rules.children.count() > 0) {
            if (rules.children.get(segment)) |child| {
                return try self.evaluatePath(&child, rule_type, context, segments, depth + 1);
            }
        }
        
        // Then check for variable patterns (e.g., $userId)
        var child_iter = rules.children.iterator();
        while (child_iter.next()) |entry| {
            const pattern = entry.key_ptr.*;
            if (std.mem.startsWith(u8, pattern, "$")) {
                // This is a variable pattern - extract the variable
                const var_name = pattern[1..];
                try context.variables.put(var_name, segment);
                
                // Continue evaluation with this path
                const allowed = try self.evaluatePath(entry.value_ptr, rule_type, context, segments, depth + 1);
                
                // Clean up the variable
                _ = context.variables.remove(var_name);
                
                if (allowed) return true;
            }
        }
        
        // Check if there's a rule at this level that should cascade
        if (rule) |r| {
            return try self.evaluateExpression(r.expression, context);
        }
        
        return false;
    }
    
    /// Evaluate a rule expression
    fn evaluateExpression(self: *RuleEvaluator, expression: []const u8, context: *RuleContext) error{OutOfMemory}!bool {
        // Trim whitespace
        const expr = std.mem.trim(u8, expression, " \t\n\r");
        
        // Handle simple cases
        if (std.mem.eql(u8, expr, "true")) return true;
        if (std.mem.eql(u8, expr, "false")) return false;
        
        // Handle auth checks
        if (std.mem.eql(u8, expr, "auth != null") or std.mem.eql(u8, expr, "auth !== null")) {
            return context.auth.authenticated;
        }
        
        if (std.mem.eql(u8, expr, "auth.uid != null") or std.mem.eql(u8, expr, "auth.uid !== null")) {
            return context.auth.uid != null;
        }
        
        // Handle variable comparisons (e.g., "$userId === auth.uid")
        if (std.mem.indexOf(u8, expr, " === ") != null or std.mem.indexOf(u8, expr, " == ") != null) {
            return try self.evaluateComparison(expr, context);
        }
        
        // Handle logical operators
        if (std.mem.indexOf(u8, expr, " && ")) |_| {
            return try self.evaluateLogicalAnd(expr, context);
        }
        
        if (std.mem.indexOf(u8, expr, " || ")) |_| {
            return try self.evaluateLogicalOr(expr, context);
        }
        
        // Unknown expression - deny by default
        log.warn("Unknown rule expression: {s}", .{expr});
        return false;
    }
    
    /// Evaluate a comparison expression
    fn evaluateComparison(self: *RuleEvaluator, expr: []const u8, context: *RuleContext) !bool {
        // Split by === or ==
        var op_pos: usize = 0;
        var op_len: usize = 0;
        
        if (std.mem.indexOf(u8, expr, " === ")) |pos| {
            op_pos = pos;
            op_len = 5;
        } else if (std.mem.indexOf(u8, expr, " == ")) |pos| {
            op_pos = pos;
            op_len = 4;
        } else {
            return false;
        }
        
        const left = std.mem.trim(u8, expr[0..op_pos], " ");
        const right = std.mem.trim(u8, expr[op_pos + op_len..], " ");
        
        const left_val = try self.resolveValue(left, context);
        const right_val = try self.resolveValue(right, context);
        
        defer self.allocator.free(left_val);
        defer self.allocator.free(right_val);
        
        return std.mem.eql(u8, left_val, right_val);
    }
    
    /// Resolve a value reference to a string
    fn resolveValue(self: *RuleEvaluator, ref: []const u8, context: *RuleContext) ![]const u8 {
        // Remove quotes if present
        if (std.mem.startsWith(u8, ref, "'") and std.mem.endsWith(u8, ref, "'")) {
            return try self.allocator.dupe(u8, ref[1..ref.len-1]);
        }
        if (std.mem.startsWith(u8, ref, "\"") and std.mem.endsWith(u8, ref, "\"")) {
            return try self.allocator.dupe(u8, ref[1..ref.len-1]);
        }
        
        // Handle auth references
        if (std.mem.eql(u8, ref, "auth.uid")) {
            if (context.auth.uid) |uid| {
                return try self.allocator.dupe(u8, uid);
            }
            return try self.allocator.dupe(u8, "null");
        }
        
        if (std.mem.eql(u8, ref, "auth.email")) {
            if (context.auth.email) |email| {
                return try self.allocator.dupe(u8, email);
            }
            return try self.allocator.dupe(u8, "null");
        }
        
        // Handle variable references (e.g., $userId)
        if (std.mem.startsWith(u8, ref, "$")) {
            const var_name = ref[1..];
            if (context.getVariable(var_name)) |val| {
                return try self.allocator.dupe(u8, val);
            }
            return try self.allocator.dupe(u8, "null");
        }
        
        // Handle null
        if (std.mem.eql(u8, ref, "null")) {
            return try self.allocator.dupe(u8, "null");
        }
        
        // Unknown reference
        return try self.allocator.dupe(u8, ref);
    }
    
    /// Evaluate logical AND expression
    fn evaluateLogicalAnd(self: *RuleEvaluator, expr: []const u8, context: *RuleContext) !bool {
        var iter = std.mem.tokenizeSequence(u8, expr, " && ");
        
        while (iter.next()) |part| {
            if (!try self.evaluateExpression(part, context)) {
                return false;
            }
        }
        
        return true;
    }
    
    /// Evaluate logical OR expression
    fn evaluateLogicalOr(self: *RuleEvaluator, expr: []const u8, context: *RuleContext) !bool {
        var iter = std.mem.tokenizeSequence(u8, expr, " || ");
        
        while (iter.next()) |part| {
            if (try self.evaluateExpression(part, context)) {
                return true;
            }
        }
        
        return false;
    }
};