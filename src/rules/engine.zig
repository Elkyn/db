const std = @import("std");
const RulesConfig = @import("rule.zig").RulesConfig;
const RuleContext = @import("rule.zig").RuleContext;
const RuleType = @import("rule.zig").RuleType;
const RulesParser = @import("parser.zig").RulesParser;
const RuleEvaluator = @import("evaluator.zig").RuleEvaluator;
const AuthContext = @import("../auth/context.zig").AuthContext;
const Storage = @import("../storage/storage.zig").Storage;
const Value = @import("../storage/value.zig").Value;
const constants = @import("../constants.zig");

const log = std.log.scoped(.rules_engine);

/// Security rules engine
pub const RulesEngine = struct {
    allocator: std.mem.Allocator,
    config: ?RulesConfig = null,
    evaluator: RuleEvaluator,
    storage: *Storage,
    
    pub fn init(allocator: std.mem.Allocator, storage: *Storage) RulesEngine {
        return .{
            .allocator = allocator,
            .evaluator = RuleEvaluator.init(allocator),
            .storage = storage,
        };
    }
    
    pub fn deinit(self: *RulesEngine) void {
        if (self.config) |*config| {
            config.deinit();
        }
    }
    
    /// Load rules from JSON string
    pub fn loadRules(self: *RulesEngine, json: []const u8) !void {
        // Clean up existing rules
        if (self.config) |*config| {
            config.deinit();
        }
        
        var parser = RulesParser.init(self.allocator);
        self.config = try parser.parse(json);
        
        log.info("Loaded security rules", .{});
    }
    
    /// Load rules from file
    pub fn loadRulesFromFile(self: *RulesEngine, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        
        const content = try file.readToEndAlloc(self.allocator, constants.MAX_RULES_FILE_SIZE);
        defer self.allocator.free(content);
        
        try self.loadRules(content);
    }
    
    /// Check if an operation is allowed
    pub fn isAllowed(
        self: *RulesEngine,
        rule_type: RuleType,
        path: []const u8,
        auth: *const AuthContext,
        new_data: ?Value,
    ) !bool {
        // If no rules configured, deny everything
        const config = self.config orelse return false;
        
        var context = RuleContext.init(self.allocator);
        defer context.deinit();
        
        // Set up context
        context.path = path;
        context.auth = .{
            .authenticated = auth.authenticated,
            .uid = auth.uid,
            .email = auth.email,
        };
        context.new_data = new_data;
        
        // Get existing data for the path
        if (self.storage.get(path)) |val| {
            // Clone the value so it persists for the context lifetime
            context.data = try val.clone(self.allocator);
        } else |_| {
            // Path doesn't exist yet
            context.data = null;
        }
        
        // Set up root accessor
        context.root_accessor = struct {
            fn accessor(p: []const u8) ?Value {
                _ = p;
                // TODO: Implement root data access
                return null;
            }
        }.accessor;
        
        // Evaluate the rules
        return try self.evaluator.evaluate(&config, rule_type, &context);
    }
    
    /// Check read permission
    pub fn canRead(self: *RulesEngine, path: []const u8, auth: *const AuthContext) !bool {
        return try self.isAllowed(.read, path, auth, null);
    }
    
    /// Check write permission
    pub fn canWrite(self: *RulesEngine, path: []const u8, auth: *const AuthContext, new_data: ?Value) !bool {
        return try self.isAllowed(.write, path, auth, new_data);
    }
};

/// Default rules for demo
pub const DEFAULT_RULES =
    \\{
    \\  "rules": {
    \\    "users": {
    \\      "$userId": {
    \\        ".read": "$userId === auth.uid",
    \\        ".write": "$userId === auth.uid",
    \\        "name": {
    \\          ".read": "true"
    \\        },
    \\        "email": {
    \\          ".read": "$userId === auth.uid"
    \\        }
    \\      }
    \\    },
    \\    "public": {
    \\      ".read": "true",
    \\      ".write": "auth != null"
    \\    },
    \\    "admin": {
    \\      ".read": "false",
    \\      ".write": "false"
    \\    }
    \\  }
    \\}
;