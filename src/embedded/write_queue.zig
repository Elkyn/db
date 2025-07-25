const std = @import("std");
const Value = @import("../storage/value.zig").Value;

pub const WriteOp = struct {
    type: enum { set, delete },
    path: []const u8,
    value: ?Value,
    callback_id: u64,
};

pub const WriteQueue = struct {
    allocator: std.mem.Allocator,
    queue: std.ArrayList(WriteOp),
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    thread: ?std.Thread,
    running: std.atomic.Value(bool),
    db: *anyopaque, // ElkynDB pointer
    pending_callbacks: std.AutoHashMap(u64, CallbackInfo),
    next_callback_id: std.atomic.Value(u64),

    const CallbackInfo = struct {
        success: bool,
        error_code: i32,
    };

    pub fn init(allocator: std.mem.Allocator, db: *anyopaque) !WriteQueue {
        return WriteQueue{
            .allocator = allocator,
            .queue = std.ArrayList(WriteOp).init(allocator),
            .mutex = .{},
            .cond = .{},
            .thread = null,
            .running = std.atomic.Value(bool).init(true),
            .db = db,
            .pending_callbacks = std.AutoHashMap(u64, CallbackInfo).init(allocator),
            .next_callback_id = std.atomic.Value(u64).init(1),
        };
    }

    pub fn deinit(self: *WriteQueue) void {
        // Stop the thread
        self.running.store(false, .seq_cst);
        self.cond.signal();
        
        if (self.thread) |thread| {
            thread.join();
        }
        
        // Clean up queue
        for (self.queue.items) |*op| {
            self.allocator.free(op.path);
            if (op.value) |*val| {
                val.deinit(self.allocator);
            }
        }
        self.queue.deinit();
        self.pending_callbacks.deinit();
    }

    pub fn start(self: *WriteQueue) !void {
        self.thread = try std.Thread.spawn(.{}, workerThread, .{self});
    }

    pub fn pushWrite(self: *WriteQueue, path: []const u8, value: Value) !u64 {
        const id = self.next_callback_id.fetchAdd(1, .seq_cst);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);
        
        var value_copy = try value.clone(self.allocator);
        errdefer value_copy.deinit(self.allocator);
        
        try self.queue.append(WriteOp{
            .type = .set,
            .path = path_copy,
            .value = value_copy,
            .callback_id = id,
        });
        
        self.cond.signal();
        return id;
    }

    pub fn pushDelete(self: *WriteQueue, path: []const u8) !u64 {
        const id = self.next_callback_id.fetchAdd(1, .seq_cst);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const path_copy = try self.allocator.dupe(u8, path);
        
        try self.queue.append(WriteOp{
            .type = .delete,
            .path = path_copy,
            .value = null,
            .callback_id = id,
        });
        
        self.cond.signal();
        return id;
    }

    pub fn waitForWrite(self: *WriteQueue, id: u64) !void {
        while (true) {
            // Check if write is complete
            {
                self.mutex.lock();
                defer self.mutex.unlock();
                
                if (self.pending_callbacks.get(id)) |info| {
                    _ = self.pending_callbacks.remove(id);
                    if (!info.success) {
                        return error.WriteFailed;
                    }
                    return;
                }
            }
            
            // Wait a bit and retry (outside mutex)
            std.time.sleep(1_000_000); // 1ms
        }
    }

    fn workerThread(self: *WriteQueue) void {
        const ElkynDB = @import("../embedded_main.zig").ElkynDB;
        const db = @as(*ElkynDB, @ptrCast(@alignCast(self.db)));
        
        while (self.running.load(.seq_cst)) {
            // Get batch of operations
            self.mutex.lock();
            
            if (self.queue.items.len == 0) {
                self.cond.wait(&self.mutex);
                self.mutex.unlock();
                continue;
            }
            
            // Take up to 100 operations
            const batch_size = @min(100, self.queue.items.len);
            var batch = self.allocator.alloc(WriteOp, batch_size) catch {
                self.mutex.unlock();
                continue;
            };
            defer self.allocator.free(batch);
            
            for (0..batch_size) |i| {
                batch[i] = self.queue.orderedRemove(0);
            }
            
            self.mutex.unlock();
            
            // Process batch
            for (batch) |*op| {
                const success = switch (op.type) {
                    .set => blk: {
                        if (op.value) |val| {
                            db.set(op.path, val, null) catch {
                                break :blk false;
                            };
                        }
                        break :blk true;
                    },
                    .delete => blk: {
                        db.delete(op.path, null) catch {
                            break :blk false;
                        };
                        break :blk true;
                    },
                };
                
                // Store result
                self.mutex.lock();
                self.pending_callbacks.put(op.callback_id, CallbackInfo{
                    .success = success,
                    .error_code = if (success) 0 else -1,
                }) catch {};
                self.mutex.unlock();
                
                // Clean up
                self.allocator.free(op.path);
                if (op.value) |*val| {
                    val.deinit(self.allocator);
                }
            }
        }
    }
};