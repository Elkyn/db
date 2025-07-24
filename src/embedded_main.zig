const std = @import("std");
const Storage = @import("storage/storage.zig").Storage;
const EventEmitter = @import("storage/event_emitter.zig").EventEmitter;
const Value = @import("storage/value.zig").Value;
const RulesEngine = @import("rules/engine.zig").RulesEngine;
const JWT = @import("auth/jwt.zig").JWT;
const AuthContext = @import("auth/context.zig").AuthContext;

// const log = std.log.scoped(.elkyn_embedded);

/// Embedded Elkyn DB - Core functionality without HTTP server
pub const ElkynDB = struct {
    allocator: std.mem.Allocator,
    storage: Storage,
    event_emitter: EventEmitter,
    rules_engine: ?RulesEngine = null,
    jwt: ?JWT = null,

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !ElkynDB {
        const storage = try Storage.init(allocator, data_dir);
        const event_emitter = EventEmitter.init(allocator);
        
        // Don't connect storage to event emitter for embedded mode to avoid issues
        // storage.setEventEmitter(&event_emitter);
        
        return ElkynDB{
            .allocator = allocator,
            .storage = storage,
            .event_emitter = event_emitter,
        };
    }

    pub fn deinit(self: *ElkynDB) void {
        if (self.rules_engine) |*engine| {
            engine.deinit();
        }
        // JWT struct doesn't have a deinit method, just clear the optional
        self.jwt = null;
        self.event_emitter.deinit();
        self.storage.deinit();
    }

    /// Enable JWT authentication
    pub fn enableAuth(self: *ElkynDB, secret: []const u8) !void {
        self.jwt = JWT.init(self.allocator, secret);
        // log.info("Authentication enabled", .{});
    }

    /// Load security rules from JSON
    pub fn enableRules(self: *ElkynDB, rules_json: []const u8) !void {
        self.rules_engine = RulesEngine.init(self.allocator, &self.storage);
        try self.rules_engine.?.loadRules(rules_json);
        // log.info("Security rules enabled", .{});
    }

    /// Get value at path (with optional auth check)
    pub fn get(self: *ElkynDB, path: []const u8, auth: ?*const AuthContext) !Value {
        // Check rules if enabled
        if (self.rules_engine) |*engine| {
            const auth_ctx = auth orelse &AuthContext{ .authenticated = false };
            const allowed = try engine.canRead(path, auth_ctx);
            if (!allowed) {
                return error.AccessDenied;
            }
        }
        
        return self.storage.get(path);
    }

    /// Set value at path (with optional auth check)
    pub fn set(self: *ElkynDB, path: []const u8, value: Value, auth: ?*const AuthContext) !void {
        // Check rules if enabled
        if (self.rules_engine) |*engine| {
            const auth_ctx = auth orelse &AuthContext{ .authenticated = false };
            const allowed = try engine.canWrite(path, auth_ctx, value);
            if (!allowed) {
                return error.AccessDenied;
            }
        }
        
        try self.storage.set(path, value);
    }

    /// Delete value at path (with optional auth check)
    pub fn delete(self: *ElkynDB, path: []const u8, auth: ?*const AuthContext) !void {
        // Check rules if enabled
        if (self.rules_engine) |*engine| {
            const auth_ctx = auth orelse &AuthContext{ .authenticated = false };
            const allowed = try engine.canWrite(path, auth_ctx, null);
            if (!allowed) {
                return error.AccessDenied;
            }
        }
        
        try self.storage.delete(path);
    }

    /// Subscribe to path changes
    pub fn subscribe(
        self: *ElkynDB,
        path: []const u8,
        callback: *const fn(@import("storage/event_emitter.zig").Event, ?*anyopaque) void,
        context: ?*anyopaque,
        include_children: bool,
    ) !u64 {
        return self.event_emitter.subscribe(path, callback, context, include_children);
    }

    /// Unsubscribe from path changes
    pub fn unsubscribe(self: *ElkynDB, subscription_id: u64) void {
        self.event_emitter.unsubscribe(subscription_id);
    }

    /// Validate JWT token and return auth context
    pub fn validateToken(self: *ElkynDB, token: []const u8) !AuthContext {
        if (self.jwt) |*jwt| {
            var result = try jwt.validate(token);
            defer result.deinit(self.allocator);
            
            if (!result.valid) {
                return error.InvalidToken;
            }
            
            var auth = AuthContext{
                .authenticated = true,
                .uid = null,
                .email = null,
                .exp = result.claims.exp,
                .token = null,
                .roles = &.{},
            };
            
            // Copy claims data
            if (result.claims.uid) |uid| {
                auth.uid = try self.allocator.dupe(u8, uid);
            }
            if (result.claims.email) |email| {
                auth.email = try self.allocator.dupe(u8, email);
            }
            auth.token = try self.allocator.dupe(u8, token);
            
            // Copy roles
            if (result.claims.roles) |roles| {
                var auth_roles = try self.allocator.alloc([]const u8, roles.len);
                for (roles, 0..) |role, i| {
                    auth_roles[i] = try self.allocator.dupe(u8, role);
                }
                auth.roles = auth_roles;
            }
            
            return auth;
        }
        
        return error.AuthNotEnabled;
    }

    /// Create JWT token (for testing/development)
    pub fn createToken(self: *ElkynDB, uid: []const u8, email: ?[]const u8) ![]const u8 {
        if (self.jwt) |*jwt| {
            const claims = @import("auth/jwt.zig").Claims{
                .uid = uid,
                .email = email,
                .iat = std.time.timestamp(),
                .exp = std.time.timestamp() + 3600, // 1 hour
            };
            return jwt.create(claims);
        }
        
        return error.AuthNotEnabled;
    }
};

// C API for bindings
export fn elkyn_init(data_dir: [*:0]const u8) ?*ElkynDB {
    var gpa = std.heap.c_allocator;
    
    const db = gpa.create(ElkynDB) catch return null;
    db.* = ElkynDB.init(gpa, std.mem.span(data_dir)) catch {
        gpa.destroy(db);
        return null;
    };
    
    return db;
}

export fn elkyn_deinit(db: *ElkynDB) void {
    const allocator = db.allocator;
    db.deinit();
    allocator.destroy(db);
}

export fn elkyn_enable_auth(db: *ElkynDB, secret: [*:0]const u8) c_int {
    db.enableAuth(std.mem.span(secret)) catch return -1;
    return 0;
}

export fn elkyn_enable_rules(db: *ElkynDB, rules_json: [*:0]const u8) c_int {
    db.enableRules(std.mem.span(rules_json)) catch return -1;
    return 0;
}

export fn elkyn_set_string(db: *ElkynDB, path: [*:0]const u8, value: [*:0]const u8, token: ?[*:0]const u8) c_int {
    const path_str = std.mem.span(path);
    const value_str = std.mem.span(value);
    
    var auth_ctx: ?AuthContext = null;
    defer if (auth_ctx) |*ctx| ctx.deinit(db.allocator);
    
    if (token) |t| {
        auth_ctx = db.validateToken(std.mem.span(t)) catch return -2; // Auth error
    }
    
    const val = Value{ .string = value_str };
    db.set(path_str, val, if (auth_ctx) |*ctx| ctx else null) catch return -1;
    return 0;
}

export fn elkyn_get_string(db: *ElkynDB, path: [*:0]const u8, token: ?[*:0]const u8) ?[*:0]u8 {
    const path_str = std.mem.span(path);
    
    var auth_ctx: ?AuthContext = null;
    defer if (auth_ctx) |*ctx| ctx.deinit(db.allocator);
    
    if (token) |t| {
        auth_ctx = db.validateToken(std.mem.span(t)) catch return null;
    }
    
    var value = db.get(path_str, if (auth_ctx) |*ctx| ctx else null) catch return null;
    defer value.deinit(db.allocator);
    
    switch (value) {
        .string => |s| {
            const result = db.allocator.dupeZ(u8, s) catch return null;
            return result.ptr;
        },
        else => return null,
    }
}

export fn elkyn_delete(db: *ElkynDB, path: [*:0]const u8, token: ?[*:0]const u8) c_int {
    const path_str = std.mem.span(path);
    
    var auth_ctx: ?AuthContext = null;
    defer if (auth_ctx) |*ctx| ctx.deinit(db.allocator);
    
    if (token) |t| {
        auth_ctx = db.validateToken(std.mem.span(t)) catch return -2;
    }
    
    db.delete(path_str, if (auth_ctx) |*ctx| ctx else null) catch return -1;
    return 0;
}

export fn elkyn_create_token(db: *ElkynDB, uid: [*:0]const u8, email: ?[*:0]const u8) ?[*:0]u8 {
    const uid_str = std.mem.span(uid);
    const email_str = if (email) |e| std.mem.span(e) else null;
    
    const token = db.createToken(uid_str, email_str) catch return null;
    const result = db.allocator.dupeZ(u8, token) catch {
        db.allocator.free(token);
        return null;
    };
    db.allocator.free(token);
    return result.ptr;
}

export fn elkyn_free_string(ptr: [*:0]u8) void {
    const allocator = std.heap.c_allocator;
    const len = std.mem.len(ptr);
    allocator.free(ptr[0..len]);
}