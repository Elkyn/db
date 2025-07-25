const std = @import("std");
const Storage = @import("storage/storage.zig").Storage;
const EventEmitter = @import("storage/event_emitter.zig").EventEmitter;
const EventQueue = @import("embedded/event_queue.zig").EventQueue;
const WriteQueue = @import("embedded/write_queue.zig").WriteQueue;
const Value = @import("storage/value.zig").Value;
const RulesEngine = @import("rules/engine.zig").RulesEngine;
const JWT = @import("auth/jwt.zig").JWT;
const AuthContext = @import("auth/context.zig").AuthContext;

// const log = std.log.scoped(.elkyn_embedded);

/// Embedded Elkyn DB - Core functionality without HTTP server
pub const ElkynDB = struct {
    allocator: std.mem.Allocator,
    storage: Storage,
    event_emitter: *EventEmitter,
    event_queue: ?*EventQueue = null,
    write_queue: ?*WriteQueue = null,
    rules_engine: ?RulesEngine = null,
    jwt: ?JWT = null,

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !ElkynDB {
        // Create the instance with uninitialized values first
        var db = ElkynDB{
            .allocator = allocator,
            .storage = undefined,
            .event_emitter = undefined,
            .event_queue = null,
            .write_queue = null,
            .rules_engine = null,
            .jwt = null,
        };
        
        // Initialize storage and event_emitter in place
        db.storage = try Storage.init(allocator, data_dir);
        
        // Allocate event emitter on heap
        db.event_emitter = try allocator.create(EventEmitter);
        db.event_emitter.* = EventEmitter.init(allocator);
        
        // Connect storage to event emitter AFTER creating the instance
        db.storage.setEventEmitter(db.event_emitter);
        
        return db;
    }

    pub fn deinit(self: *ElkynDB) void {
        if (self.rules_engine) |*engine| {
            engine.deinit();
        }
        if (self.write_queue) |queue| {
            queue.deinit();
            self.allocator.destroy(queue);
        }
        if (self.event_queue) |queue| {
            // TODO: Unsubscribe from event emitter
            queue.deinit();
            self.allocator.destroy(queue);
        }
        // JWT struct doesn't have a deinit method, just clear the optional
        self.jwt = null;
        self.event_emitter.deinit();
        self.allocator.destroy(self.event_emitter);
        self.storage.deinit();
    }

    /// Enable event queue for Node.js bindings
    pub fn enableEventQueue(self: *ElkynDB) !void {
        if (self.event_queue != null) return; // Already enabled
        
        // std.debug.print("enableEventQueue: creating event queue\n", .{});
        
        // Create event queue
        const queue = try self.allocator.create(EventQueue);
        queue.* = try EventQueue.init(self.allocator);
        self.event_queue = queue;
        
        // Subscribe to all events and forward to queue
        _ = try self.event_emitter.subscribe(
            "/", // Watch everything
            eventQueueCallback,
            queue, // Pass queue as context
            true, // Include children
        );
        
        // std.debug.print("enableEventQueue: subscribed with id={d}\n", .{subscription_id});
    }
    
    fn eventQueueCallback(event: @import("storage/event_emitter.zig").Event, context: ?*anyopaque) void {
        const queue = @as(*EventQueue, @ptrCast(@alignCast(context.?)));
        
        
        // Map event type
        const event_type: EventQueue.EventType = switch (event.type) {
            .value_changed, .child_added, .child_changed => .change,
            .value_deleted, .child_removed => .delete,
        };
        
        // Push to queue (ignore errors for now)
        queue.push(event_type, event.path, event.value) catch {};
            // std.debug.print("eventQueueCallback: failed to push event: {any}\n", .{err});
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
    
    /// Enable write queue for async writes
    pub fn enableWriteQueue(self: *ElkynDB) !void {
        if (self.write_queue != null) return; // Already enabled
        
        const queue = try self.allocator.create(WriteQueue);
        queue.* = try WriteQueue.init(self.allocator, self);
        self.write_queue = queue;
        
        try queue.start();
    }
    
    /// Async set - returns immediately, write happens in background
    pub fn setAsync(self: *ElkynDB, path: []const u8, value: Value, auth: ?*const AuthContext) !u64 {
        // Check rules if enabled
        if (self.rules_engine) |*engine| {
            const auth_ctx = auth orelse &AuthContext{ .authenticated = false };
            const allowed = try engine.canWrite(path, auth_ctx, value);
            if (!allowed) {
                return error.AccessDenied;
            }
        }
        
        const queue = self.write_queue orelse return error.WriteQueueNotEnabled;
        return try queue.pushWrite(path, value);
    }
    
    /// Async delete - returns immediately, delete happens in background
    pub fn deleteAsync(self: *ElkynDB, path: []const u8, auth: ?*const AuthContext) !u64 {
        // Check rules if enabled
        if (self.rules_engine) |*engine| {
            const auth_ctx = auth orelse &AuthContext{ .authenticated = false };
            const allowed = try engine.canWrite(path, auth_ctx, null);
            if (!allowed) {
                return error.AccessDenied;
            }
        }
        
        const queue = self.write_queue orelse return error.WriteQueueNotEnabled;
        return try queue.pushDelete(path);
    }
    
    /// Wait for async write to complete
    pub fn waitForWrite(self: *ElkynDB, id: u64) !void {
        const queue = self.write_queue orelse return error.WriteQueueNotEnabled;
        return try queue.waitForWrite(id);
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
    
    // std.debug.print("elkyn_init: created db at {*} for dir={s}\n", .{db, std.mem.span(data_dir)});
    
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
    
    // Create a string value directly (no JSON parsing)
    const duped_str = db.allocator.dupe(u8, value_str) catch return -1;
    var val = Value{ .string = duped_str };
    defer val.deinit(db.allocator);
    
    db.set(path_str, val, if (auth_ctx) |*ctx| ctx else null) catch {
        return -1;
    };
    
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
    
    // Convert any Value type to string representation for C interface
    switch (value) {
        .string => |s| {
            const result = db.allocator.dupeZ(u8, s) catch return null;
            return result.ptr;
        },
        .number => |n| {
            const str = std.fmt.allocPrint(db.allocator, "{d}", .{n}) catch return null;
            const result = db.allocator.dupeZ(u8, str) catch {
                db.allocator.free(str);
                return null;
            };
            db.allocator.free(str);
            return result.ptr;
        },
        .boolean => |b| {
            const str = if (b) "true" else "false";
            const result = db.allocator.dupeZ(u8, str) catch return null;
            return result.ptr;
        },
        .null => {
            const result = db.allocator.dupeZ(u8, "null") catch return null;
            return result.ptr;
        },
        .array, .object => {
            // For complex types, return as JSON string
            const json = value.toJson(db.allocator) catch return null;
            const result = db.allocator.dupeZ(u8, json) catch {
                db.allocator.free(json);
                return null;
            };
            db.allocator.free(json);
            return result.ptr;
        },
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

export fn elkyn_set_binary(db: *ElkynDB, path: [*:0]const u8, data: [*]const u8, length: usize, token: ?[*:0]const u8) c_int {
    const path_str = std.mem.span(path);
    const data_slice = data[0..length];
    
    var auth_ctx: ?AuthContext = null;
    defer if (auth_ctx) |*ctx| ctx.deinit(db.allocator);
    
    if (token) |t| {
        auth_ctx = db.validateToken(std.mem.span(t)) catch return -2; // Auth error
    }
    
    // Deserialize MessagePack directly
    var val = Value.fromMessagePack(db.allocator, data_slice) catch return -1;
    defer val.deinit(db.allocator);
    
    db.set(path_str, val, if (auth_ctx) |*ctx| ctx else null) catch {
        return -1;
    };
    
    return 0;
}

export fn elkyn_get_binary(db: *ElkynDB, path: [*:0]const u8, length: *usize, token: ?[*:0]const u8) ?[*]u8 {
    const path_str = std.mem.span(path);
    
    var auth_ctx: ?AuthContext = null;
    defer if (auth_ctx) |*ctx| ctx.deinit(db.allocator);
    
    if (token) |t| {
        auth_ctx = db.validateToken(std.mem.span(t)) catch return null;
    }
    
    var value = db.get(path_str, if (auth_ctx) |*ctx| ctx else null) catch return null;
    defer value.deinit(db.allocator);
    
    // Serialize to MessagePack
    const binary_data = value.toMessagePack(db.allocator) catch return null;
    
    // Allocate with C allocator for returning to C++ 
    const result = std.heap.c_allocator.alloc(u8, binary_data.len) catch {
        db.allocator.free(binary_data);
        return null;
    };
    
    @memcpy(result, binary_data);
    db.allocator.free(binary_data);
    
    length.* = result.len;
    return result.ptr;
}

// Zero-copy read info structure
pub const ReadInfo = extern struct {
    data: [*]const u8,
    length: usize,
    type_tag: u8, // 's' = string, 'n' = number, 'b' = bool, 'z' = null, 'm' = msgpack
    needs_free: bool,
};

// Zero-copy read for primitives
export fn elkyn_get_raw(db: *ElkynDB, path: [*:0]const u8, info: *ReadInfo, token: ?[*:0]const u8) c_int {
    const path_str = std.mem.span(path);
    
    var auth_ctx: ?AuthContext = null;
    defer if (auth_ctx) |*ctx| ctx.deinit(db.allocator);
    
    if (token) |t| {
        auth_ctx = db.validateToken(std.mem.span(t)) catch return -2;
    }
    
    // Get raw data from storage
    const raw_data = db.storage.getRaw(path_str) catch return -1;
    
    if (raw_data.len == 0) return -1;
    
    // Check type and return appropriate info
    switch (raw_data[0]) {
        's' => {
            // String - can return zero-copy
            info.data = raw_data.ptr + 1;
            info.length = raw_data.len - 1;
            info.type_tag = 's';
            info.needs_free = false;
        },
        'n' => {
            // Number - return raw bytes
            info.data = raw_data.ptr;
            info.length = raw_data.len;
            info.type_tag = 'n';
            info.needs_free = false;
        },
        'b', 'z' => {
            // Boolean/null - return as-is
            info.data = raw_data.ptr;
            info.length = raw_data.len;
            info.type_tag = raw_data[0];
            info.needs_free = false;
        },
        else => {
            // Complex type - need to serialize
            var value = db.get(path_str, if (auth_ctx) |*ctx| ctx else null) catch return -1;
            defer value.deinit(db.allocator);
            
            const msgpack = value.toMessagePack(db.allocator) catch return -1;
            const result = std.heap.c_allocator.alloc(u8, msgpack.len) catch {
                db.allocator.free(msgpack);
                return -1;
            };
            
            @memcpy(result, msgpack);
            db.allocator.free(msgpack);
            
            info.data = result.ptr;
            info.length = result.len;
            info.type_tag = 'm';
            info.needs_free = true;
        }
    }
    
    return 0;
}

// Event Queue exports
export fn elkyn_enable_event_queue(db: *ElkynDB) c_int {
    // std.debug.print("elkyn_enable_event_queue: db at {*}\n", .{db});
    db.enableEventQueue() catch return -1;
    return 0;
}

const C_EventData = extern struct {
    type: u8,
    path: [*:0]const u8,
    value: ?[*:0]const u8,
    sequence: u64,
    timestamp: i64,
};

export fn elkyn_event_queue_pop_batch(db: *ElkynDB, buffer: [*]C_EventData, max_count: usize) usize {
    const queue = db.event_queue orelse return 0;
    
    var count: usize = 0;
    while (count < max_count) : (count += 1) {
        const event = queue.pop() orelse break;
        
        // Now event.path is a fixed array, so we need to slice it
        const path_slice = event.path[0..event.path_len];
        
        // std.debug.print("elkyn_event_queue_pop_batch: event path={s} len={d}\n", .{path_slice, event.path_len});
        
        // Create C-compatible strings
        const path_z = std.heap.c_allocator.dupeZ(u8, path_slice) catch break;
        
        // Create value string if present
        var value_z: ?[*:0]const u8 = null;
        if (event.value) |val| {
            const value_z_str = std.heap.c_allocator.dupeZ(u8, val) catch break;
            value_z = value_z_str.ptr;
        }
        
        buffer[count] = C_EventData{
            .type = @intFromEnum(event.type),
            .path = path_z.ptr,
            .value = value_z,
            .sequence = event.sequence,
            .timestamp = event.timestamp,
        };
    }
    
    return count;
}

export fn elkyn_event_queue_pending(db: *ElkynDB) usize {
    const queue = db.event_queue orelse return 0;
    return queue.pending();
}

// Write queue exports
export fn elkyn_enable_write_queue(db: *ElkynDB) c_int {
    db.enableWriteQueue() catch return -1;
    return 0;
}

export fn elkyn_set_async(db: *ElkynDB, path: [*:0]const u8, data: [*]const u8, length: usize, token: ?[*:0]const u8) u64 {
    const path_str = std.mem.span(path);
    const data_slice = data[0..length];
    
    var auth_ctx: ?AuthContext = null;
    defer if (auth_ctx) |*ctx| ctx.deinit(db.allocator);
    
    if (token) |t| {
        auth_ctx = db.validateToken(std.mem.span(t)) catch return 0; // 0 = error
    }
    
    // Deserialize MessagePack directly
    var val = Value.fromMessagePack(db.allocator, data_slice) catch return 0;
    defer val.deinit(db.allocator);
    
    const id = db.setAsync(path_str, val, if (auth_ctx) |*ctx| ctx else null) catch return 0;
    return id;
}

export fn elkyn_delete_async(db: *ElkynDB, path: [*:0]const u8, token: ?[*:0]const u8) u64 {
    const path_str = std.mem.span(path);
    
    var auth_ctx: ?AuthContext = null;
    defer if (auth_ctx) |*ctx| ctx.deinit(db.allocator);
    
    if (token) |t| {
        auth_ctx = db.validateToken(std.mem.span(t)) catch return 0; // 0 = error
    }
    
    const id = db.deleteAsync(path_str, if (auth_ctx) |*ctx| ctx else null) catch return 0;
    return id;
}

export fn elkyn_wait_for_write(db: *ElkynDB, id: u64) c_int {
    db.waitForWrite(id) catch return -1;
    return 0;
}