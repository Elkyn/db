const std = @import("std");

/// Rule type - what operation is being checked
pub const RuleType = enum {
    read,
    write,
    validate,
    index,
};

/// A single rule expression
pub const Rule = struct {
    /// The rule expression as a string
    expression: []const u8,
    
    /// Compiled rule function (if pre-compiled)
    compiled_fn: ?*const fn (context: RuleContext) bool = null,
    
    pub fn deinit(self: *Rule, allocator: std.mem.Allocator) void {
        allocator.free(self.expression);
    }
};

/// Context for rule evaluation
pub const RuleContext = struct {
    /// Authentication context
    auth: struct {
        uid: ?[]const u8 = null,
        email: ?[]const u8 = null,
        authenticated: bool = false,
    },
    
    /// Path being accessed
    path: []const u8,
    
    /// Path variables (e.g., $userId from /users/$userId)
    variables: std.StringHashMap([]const u8),
    
    /// New data being written (for write operations)
    new_data: ?@import("../storage/value.zig").Value = null,
    
    /// Existing data at the path
    data: ?@import("../storage/value.zig").Value = null,
    
    /// Root data accessor for cross-references
    root_accessor: ?*const fn (path: []const u8) ?@import("../storage/value.zig").Value = null,
    
    pub fn init(allocator: std.mem.Allocator) RuleContext {
        return .{
            .auth = .{},
            .path = "",
            .variables = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *RuleContext) void {
        self.variables.deinit();
    }
    
    /// Get a path variable value
    pub fn getVariable(self: *const RuleContext, name: []const u8) ?[]const u8 {
        return self.variables.get(name);
    }
};

/// Rules for a specific path pattern
pub const PathRules = struct {
    /// Path pattern (e.g., "/users/$userId")
    pattern: []const u8,
    
    /// Read rule
    read: ?Rule = null,
    
    /// Write rule
    write: ?Rule = null,
    
    /// Validation rule
    validate: ?Rule = null,
    
    /// Indexing rules
    index: ?[]const []const u8 = null,
    
    /// Child rules
    children: std.StringHashMap(PathRules),
    
    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) !PathRules {
        return PathRules{
            .pattern = try allocator.dupe(u8, pattern),
            .children = std.StringHashMap(PathRules).init(allocator),
        };
    }
    
    pub fn deinit(self: *PathRules, allocator: std.mem.Allocator) void {
        allocator.free(self.pattern);
        
        if (self.read) |*rule| rule.deinit(allocator);
        if (self.write) |*rule| rule.deinit(allocator);
        if (self.validate) |*rule| rule.deinit(allocator);
        
        var iter = self.children.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.children.deinit();
    }
};

/// Complete rules configuration
pub const RulesConfig = struct {
    allocator: std.mem.Allocator,
    
    /// Root rules
    root: PathRules,
    
    pub fn init(allocator: std.mem.Allocator) !RulesConfig {
        return RulesConfig{
            .allocator = allocator,
            .root = try PathRules.init(allocator, "/"),
        };
    }
    
    pub fn deinit(self: *RulesConfig) void {
        self.root.deinit(self.allocator);
    }
};