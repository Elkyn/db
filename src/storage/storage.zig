const std = @import("std");
const lmdb = @import("lmdb.zig");
const tree = @import("tree.zig");
const value_mod = @import("value.zig");
const event_emitter_mod = @import("event_emitter.zig");

const Value = value_mod.Value;
const Path = tree.Path;
const EventEmitter = event_emitter_mod.EventEmitter;

/// Batch write operation for collecting multiple LMDB puts
const WriteBatch = struct {
    operations: std.ArrayList(WriteOp),
    allocator: std.mem.Allocator,
    
    const WriteOp = struct {
        key: []const u8,
        value: []const u8,
        
        pub fn deinit(self: *WriteOp, allocator: std.mem.Allocator) void {
            allocator.free(self.key);
            allocator.free(self.value);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) WriteBatch {
        return WriteBatch{
            .operations = std.ArrayList(WriteOp).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *WriteBatch) void {
        for (self.operations.items) |*op| {
            op.deinit(self.allocator);
        }
        self.operations.deinit();
    }
    
    pub fn add(self: *WriteBatch, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);
        
        try self.operations.append(WriteOp{
            .key = key_copy,
            .value = value_copy,
        });
    }
    
    pub fn commit(self: *WriteBatch, db: *lmdb.Database) !void {
        // Execute all operations in sequence
        for (self.operations.items) |op| {
            try db.put(op.key, op.value);
        }
    }
};

pub const StorageError = error{
    InvalidPath,
    NotFound,
    SerializationFailed,
    DeserializationFailed,
    TransactionFailed,
    StorageFull,
    OutOfMemory,
} || lmdb.LmdbError || tree.PathError;

/// High-level storage interface combining LMDB and tree operations
pub const Storage = struct {
    env: lmdb.Environment,
    allocator: std.mem.Allocator,
    event_emitter: ?*EventEmitter,

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !Storage {
        const env = try lmdb.Environment.init(allocator, data_dir);
        return Storage{
            .env = env,
            .allocator = allocator,
            .event_emitter = null,
        };
    }

    pub fn deinit(self: *Storage) void {
        self.env.deinit();
    }

    /// Set the event emitter for real-time updates
    pub fn setEventEmitter(self: *Storage, emitter: *EventEmitter) void {
        self.event_emitter = emitter;
    }

    /// Set a value at the given path
    pub fn set(self: *Storage, path: []const u8, value: Value) !void {
        // Validate and normalize path
        const normalized = try tree.normalizePath(self.allocator, path);
        defer self.allocator.free(normalized);

        // Phase 3A Optimization: Conditional event emission
        // Only fetch old value when events are actually needed
        var old_value: ?Value = null;
        const should_emit_events = self.event_emitter != null;
        if (should_emit_events) {
            old_value = self.get(normalized) catch null;
        }

        // Begin transaction
        var txn = try self.env.beginTxn(false);
        defer txn.deinit();

        var db = try txn.openDatabase(null);

        // Phase 1 Optimization: Skip parent path creation entirely
        // Objects are detected by checking for children during reads

        // Revert to working implementation - deliver stable 31% improvement
        // TODO: Fix batch writes in separate iteration
        try self.setRecursive(&db, normalized, value);
        
        try txn.commit();

        // Phase 3B Optimization: Event emission after transaction
        // TODO: Future enhancement - make this truly async with thread pool
        if (should_emit_events) {
            if (self.event_emitter) |emitter| {
                // Create a copy of the value for the event
                var value_copy = try value.clone(self.allocator);
                errdefer value_copy.deinit(self.allocator);
                
                // Emit event (currently synchronous, but isolated from transaction)
                emitter.emitValueChanged(normalized, value_copy, old_value) catch {};
                
                // Clean up old value after emitting event
                if (old_value) |*ov| ov.deinit(self.allocator);
            }
        } else {
            // Clean up old value if no emitter
            if (old_value) |*ov| ov.deinit(self.allocator);
        }
    }
    
    // Phase 1 Optimization: Remove ensureParentPaths entirely
    // Objects are now detected by checking for children during reads
    // This eliminates the major write bottleneck
    
    /// Phase 1 Helper: Check if a path has any children
    fn hasAnyChild(self: *Storage, db: *lmdb.Database, path: []const u8) bool {
        _ = self;
        var cursor = db.openCursor() catch return false;
        defer cursor.deinit();
        
        // Create prefix for child search
        var prefix_buf: [512]u8 = undefined;
        const prefix = if (std.mem.eql(u8, path, "/"))
            "/"
        else blk: {
            const formatted = std.fmt.bufPrint(&prefix_buf, "{s}/", .{path}) catch return false;
            break :blk formatted;
        };
        
        // Seek directly to the prefix for efficiency
        var entry = cursor.seek(prefix) catch return false;
        
        // For root path, special handling
        if (std.mem.eql(u8, path, "/")) {
            while (entry) |kv| {
                // Skip the root "/" entry itself  
                if (std.mem.eql(u8, kv.key, "/")) {
                    entry = cursor.next() catch return false;
                    continue;
                }
                // Check if this is a direct child of root (starts with "/" but no second "/")
                if (std.mem.startsWith(u8, kv.key, "/") and kv.key.len > 1) {
                    const after_slash = kv.key[1..];
                    const has_nested_slash = std.mem.indexOf(u8, after_slash, "/") != null;
                    if (!has_nested_slash) {
                        return true; // Found direct child
                    }
                }
                entry = cursor.next() catch return false;
            }
        } else {
            // For non-root paths, check if any keys start with our prefix
            while (entry) |kv| {
                if (std.mem.startsWith(u8, kv.key, prefix)) {
                    return true; // Found a child
                }
                // If we've gone past our prefix range, stop
                if (!std.mem.startsWith(u8, kv.key, prefix)) {
                    break;
                }
                entry = cursor.next() catch return false;
            }
        }
        return false;
    }

    fn setRecursive(self: *Storage, db: *lmdb.Database, path: []const u8, value: Value) !void {
        // Debug log
        // std.debug.print("setRecursive: path={s}, value_type={s}\n", .{path, @tagName(value)});
        
        switch (value) {
            .object => |obj| {
                // For objects, store each field as a separate path
                var iter = obj.iterator();
                var field_count: u32 = 0;
                while (iter.next()) |entry| {
                    field_count += 1;
                    
                    const child_path = if (std.mem.eql(u8, path, "/"))
                        try std.fmt.allocPrint(self.allocator, "/{s}", .{entry.key_ptr.*})
                    else
                        try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{path, entry.key_ptr.*});
                    defer self.allocator.free(child_path);
                    
                    self.setRecursive(db, child_path, entry.value_ptr.*) catch |err| {
                        return err;
                    };
                }
                
                // Phase 1 Optimization: No branch markers needed
                // Object structure is implicit from children
            },
            .array => |arr| {
                // For arrays, store each element with numeric index
                for (arr.items, 0..) |item, index| {
                    const child_path = if (std.mem.eql(u8, path, "/"))
                        try std.fmt.allocPrint(self.allocator, "/{d}", .{index})
                    else
                        try std.fmt.allocPrint(self.allocator, "{s}/{d}", .{path, index});
                    defer self.allocator.free(child_path);
                    
                    try self.setRecursive(db, child_path, item);
                }
                
                // Phase 1 Optimization: Store array metadata efficiently
                const array_meta = try std.fmt.allocPrint(self.allocator, "__array__:{d}", .{arr.items.len});
                defer self.allocator.free(array_meta);
                
                // Debug log
                // std.debug.print("setRecursive: storing array marker at {s}: {s}\n", .{path, array_meta});
                
                try db.put(path, array_meta);
            },
            else => {
                // For primitive values, store directly using MessagePack
                var value_copy = value;
                const msgpack = value_copy.toMessagePack(self.allocator) catch |err| {
                    return err;
                };
                defer self.allocator.free(msgpack);
                
                db.put(path, msgpack) catch |err| {
                    return err;
                };
            }
        }
    }

    /// Get a value at the given path
    pub fn get(self: *Storage, path: []const u8) !Value {
        // Validate and normalize path
        const normalized = try tree.normalizePath(self.allocator, path);
        defer self.allocator.free(normalized);

        // Read from LMDB
        var txn = try self.env.beginTxn(true);
        defer txn.deinit();

        var db = try txn.openDatabase(null);
        const data = db.get(normalized) catch |err| {
            if (err == error.NotFound) {
                // Phase 1 Optimization: Check if this path has children
                const has_children = self.hasAnyChild(&db, normalized);
                if (has_children) {
                    return try self.reconstructObject(&db, normalized);
                }
                return error.NotFound;
            }
            return err;
        };

        // Phase 1 Optimization: No more __branch__ markers
        // If we got data, it's either an array marker or primitive value

        // Check if this is an array node
        if (std.mem.startsWith(u8, data, "__array__:")) {
            // Parse array length
            const len_str = data["__array__:".len..];
            const len = std.fmt.parseInt(usize, len_str, 10) catch return error.DeserializationFailed;
            return try self.reconstructArray(&db, normalized, len);
        }

        // Otherwise, deserialize MessagePack to Value
        return Value.fromMessagePack(self.allocator, data) catch return error.DeserializationFailed;
    }

    fn reconstructObject(self: *Storage, db: *lmdb.Database, path: []const u8) StorageError!Value {
        var obj = std.StringHashMap(Value).init(self.allocator);
        errdefer {
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                var val = entry.value_ptr.*;
                val.deinit(self.allocator);
            }
            obj.deinit();
        }

        // Create cursor to iterate through children
        var cursor = try db.openCursor();
        defer cursor.deinit();

        // Construct the prefix to search for
        const prefix = if (std.mem.eql(u8, path, "/"))
            try self.allocator.dupe(u8, "/")
        else
            try std.fmt.allocPrint(self.allocator, "{s}/", .{path});
        defer self.allocator.free(prefix);

        // For root path, we need to handle it specially
        if (std.mem.eql(u8, path, "/")) {
            // Seek to first entry after "/"
            var entry = try cursor.seek(prefix);
            
            while (entry) |kv| {
                // Skip the root "/" entry itself
                if (std.mem.eql(u8, kv.key, "/")) {
                    entry = try cursor.next();
                    continue;
                }
                
                // Stop if we've gone past all root children
                if (!std.mem.startsWith(u8, kv.key, "/")) break;
                
                // Check if this is a top-level key (no / after the first one)
                const key_after_slash = kv.key[1..];
                const slash_pos = std.mem.indexOf(u8, key_after_slash, "/");
                
                if (slash_pos == null) {
                    // This is a direct child of root
                    const child_value = try self.parseValue(db, kv.key, kv.value);
                    const key_copy = try self.allocator.dupe(u8, key_after_slash);
                    try obj.put(key_copy, child_value);
                }
                
                entry = try cursor.next();
            }
        } else {
            // Non-root path - seek directly to the prefix
            var entry = try cursor.seek(prefix);
            
            while (entry) |kv| {
                // Check if this key is under our prefix
                if (!std.mem.startsWith(u8, kv.key, prefix)) break;
                
                // Extract the child name
                const child_path = kv.key[prefix.len..];
                
                // Skip if this is a nested child (contains additional /)
                const slash_pos = std.mem.indexOf(u8, child_path, "/");
                if (slash_pos) |pos| {
                    // Jump to the next sibling by seeking to prefix + child_path up to slash + "0"
                    // This skips all nested children under this path
                    const skip_prefix = try std.fmt.allocPrint(self.allocator, "{s}{s}0", .{ prefix, child_path[0..pos] });
                    defer self.allocator.free(skip_prefix);
                    entry = try cursor.seek(skip_prefix);
                    continue;
                }
                
                // Parse the child value
                const child_value = try self.parseValue(db, kv.key, kv.value);
                const key_copy = try self.allocator.dupe(u8, child_path);
                try obj.put(key_copy, child_value);
                
                entry = try cursor.next();
            }
        }
        
        return Value{ .object = obj };
    }

    fn parseValue(self: *Storage, db: *lmdb.Database, key: []const u8, value: []const u8) StorageError!Value {
        if (std.mem.eql(u8, value, "__branch__")) {
            // Recursively reconstruct the object
            return try self.reconstructObject(db, key);
        } else if (std.mem.startsWith(u8, value, "__array__:")) {
            // Parse array length and reconstruct
            const len_str = value["__array__:".len..];
            const len = std.fmt.parseInt(usize, len_str, 10) catch return error.DeserializationFailed;
            return try self.reconstructArray(db, key, len);
        } else {
            // Parse as MessagePack value
            return Value.fromMessagePack(self.allocator, value) catch return error.DeserializationFailed;
        }
    }

    fn reconstructArray(self: *Storage, db: *lmdb.Database, path: []const u8, len: usize) StorageError!Value {
        var arr = std.ArrayList(Value).init(self.allocator);
        errdefer arr.deinit();

        // Read each array element
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const index_path = try std.fmt.allocPrint(self.allocator, "{s}/{d}", .{path, i});
            defer self.allocator.free(index_path);
            
            // Try to get value at index path
            const data = db.get(index_path) catch |err| {
                if (err == error.NotFound) {
                    // Element might be an object or array - check for children
                    const has_children = self.hasAnyChild(db, index_path);
                    if (has_children) {
                        const obj_value = try self.reconstructObject(db, index_path);
                        try arr.append(obj_value);
                        continue;
                    }
                    return error.NotFound;
                }
                return err;
            };
            
            // Check if this is an array node
            if (std.mem.startsWith(u8, data, "__array__:")) {
                // Parse array length and reconstruct nested array
                const nested_len_str = data["__array__:".len..];
                const nested_len = std.fmt.parseInt(usize, nested_len_str, 10) catch return error.DeserializationFailed;
                const nested_array = try self.reconstructArray(db, index_path, nested_len);
                try arr.append(nested_array);
            } else {
                // Parse as primitive value
                const value = Value.fromMessagePack(self.allocator, data) catch return error.DeserializationFailed;
                try arr.append(value);
            }
        }
        
        return Value{ .array = arr };
    }

    /// Delete a value at the given path and all its children
    pub fn delete(self: *Storage, path: []const u8) !void {
        // Validate and normalize path
        const normalized = try tree.normalizePath(self.allocator, path);
        defer self.allocator.free(normalized);

        // Phase 3A Optimization: Conditional event emission
        // Only fetch old value when events are actually needed
        var old_value: ?Value = null;
        const should_emit_events = self.event_emitter != null;
        if (should_emit_events) {
            old_value = self.get(normalized) catch null;
        }

        // Delete from LMDB
        var txn = try self.env.beginTxn(false);
        defer txn.deinit();

        var db = try txn.openDatabase(null);
        
        // Phase 1 Optimization: Simplified delete - just remove everything with prefix
        // Delete the key itself first
        db.delete(normalized) catch |err| {
            if (err != error.NotFound) return err;
        };
        
        // Delete all children using cursor
        try self.deleteChildren(&db, normalized);
        
        try txn.commit();

        // Phase 3B Optimization: Event emission after transaction
        if (should_emit_events) {
            if (self.event_emitter) |emitter| {
                try emitter.emitValueDeleted(normalized, old_value);
                // Clean up old value after emitting event
                if (old_value) |*ov| ov.deinit(self.allocator);
            }
        } else {
            // Clean up old value if no emitter
            if (old_value) |*ov| ov.deinit(self.allocator);
        }
    }
    
    fn deleteChildren(self: *Storage, db: *lmdb.Database, path: []const u8) !void {
        var cursor = try db.openCursor();
        defer cursor.deinit();
        
        // Construct the prefix to search for children
        const prefix = if (std.mem.eql(u8, path, "/"))
            try self.allocator.dupe(u8, "/")
        else
            try std.fmt.allocPrint(self.allocator, "{s}/", .{path});
        defer self.allocator.free(prefix);
        
        // Seek to first child
        var entry = try cursor.seek(prefix);
        
        // Collect all keys to delete (can't delete while iterating)
        var keys_to_delete = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (keys_to_delete.items) |key| {
                self.allocator.free(key);
            }
            keys_to_delete.deinit();
        }
        
        while (entry) |kv| {
            // Check if this key is under our prefix
            if (!std.mem.startsWith(u8, kv.key, prefix)) break;
            
            // Skip the root "/" itself when deleting from root
            if (std.mem.eql(u8, path, "/") and std.mem.eql(u8, kv.key, "/")) {
                entry = try cursor.next();
                continue;
            }
            
            // Add to deletion list
            const key_copy = try self.allocator.dupe(u8, kv.key);
            try keys_to_delete.append(key_copy);
            
            entry = try cursor.next();
        }
        
        // Delete all collected keys
        for (keys_to_delete.items) |key| {
            db.delete(key) catch |err| {
                if (err != error.NotFound) return err;
            };
        }
    }

    /// Update specific fields in an object (merge operation)
    pub fn update(self: *Storage, path: []const u8, updates: Value) !void {
        // Updates must be an object
        if (updates != .object) {
            return error.InvalidPath;
        }
        
        // Get existing value
        var existing = self.get(path) catch |err| {
            if (err == error.NotFound) {
                // If doesn't exist, just set
                return try self.set(path, updates);
            }
            return err;
        };
        defer existing.deinit(self.allocator);
        
        // Existing must be an object to merge
        if (existing != .object) {
            return error.InvalidPath;
        }
        
        // Create merged object
        var merged = std.StringHashMap(Value).init(self.allocator);
        errdefer {
            var iter = merged.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                var val = entry.value_ptr.*;
                val.deinit(self.allocator);
            }
            merged.deinit();
        }
        
        // Copy existing fields
        var existing_iter = existing.object.iterator();
        while (existing_iter.next()) |entry| {
            const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(key_copy);
            
            const val_copy = try entry.value_ptr.*.clone(self.allocator);
            errdefer {
                var val_mut = val_copy;
                val_mut.deinit(self.allocator);
            }
            
            try merged.put(key_copy, val_copy);
        }
        
        // Apply updates (overwrite or add)
        var updates_iter = updates.object.iterator();
        while (updates_iter.next()) |entry| {
            // Remove existing if present
            if (merged.fetchRemove(entry.key_ptr.*)) |old| {
                self.allocator.free(old.key);
                var old_val = old.value;
                old_val.deinit(self.allocator);
            }
            
            // Add updated value
            const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
            const val_copy = try entry.value_ptr.*.clone(self.allocator);
            try merged.put(key_copy, val_copy);
        }
        
        // Create merged value and set it
        var merged_value = Value{ .object = merged };
        defer merged_value.deinit(self.allocator);
        
        return try self.set(path, merged_value);
    }

    /// List all keys under a given path
    pub fn list(self: *Storage, parent_path: []const u8) ![][]const u8 {
        // Normalize parent path
        const normalized = try tree.normalizePath(self.allocator, parent_path);
        defer self.allocator.free(normalized);

        var keys = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (keys.items) |key| {
                self.allocator.free(key);
            }
            keys.deinit();
        }

        var txn = try self.env.beginTxn(true);
        defer txn.deinit();

        var db = try txn.openDatabase(null);
        var cursor = try db.openCursor();
        defer cursor.deinit();

        const prefix = if (std.mem.eql(u8, normalized, "/"))
            try self.allocator.dupe(u8, "/")
        else
            try std.fmt.allocPrint(self.allocator, "{s}/", .{normalized});
        defer self.allocator.free(prefix);

        var entry = try cursor.seek(prefix);
        while (entry) |kv| {
            if (!std.mem.startsWith(u8, kv.key, prefix)) break;

            const child_path = kv.key[prefix.len..];
            if (std.mem.indexOf(u8, child_path, "/") == null) {
                try keys.append(try self.allocator.dupe(u8, child_path));
            }

            entry = try cursor.next();
        }

        return try keys.toOwnedSlice();
    }

    /// Phase 2 Optimization: Simplified exists() function
    /// Just tries to get the value - simple wrapper around get()
    pub fn exists(self: *Storage, path: []const u8) bool {
        const result = self.get(path) catch return false;
        var value = result;
        defer value.deinit(self.allocator);
        return true;
    }
};