const std = @import("std");
const SABQueue = @import("sab_queue.zig").SABQueue;
const Value = @import("../storage/value.zig").Value;

/// Worker thread that processes SharedArrayBuffer operations
pub const SABWorker = struct {
    allocator: std.mem.Allocator,
    queue: *SABQueue,
    thread: ?std.Thread,
    db: *anyopaque, // ElkynDB pointer
    running: std.atomic.Value(bool),
    
    pub fn init(allocator: std.mem.Allocator, queue: *SABQueue, db: *anyopaque) SABWorker {
        return SABWorker{
            .allocator = allocator,
            .queue = queue,
            .thread = null,
            .db = db,
            .running = std.atomic.Value(bool).init(true),
        };
    }
    
    pub fn start(self: *SABWorker) !void {
        self.thread = try std.Thread.spawn(.{}, workerMain, .{self});
    }
    
    pub fn stop(self: *SABWorker) void {
        self.running.store(false, .release);
        self.queue.shutdown();
        
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }
    
    fn workerMain(self: *SABWorker) void {
        const ElkynDB = @import("../embedded_main.zig").ElkynDB;
        const db = @as(*ElkynDB, @ptrCast(@alignCast(self.db)));
        
        std.log.info("SAB worker thread started", .{});
        
        var operations_processed: u64 = 0;
        var batch_count: u64 = 0;
        
        while (self.running.load(.acquire)) {
            // Process available operations
            var batch_size: u32 = 0;
            const batch_start = std.time.nanoTimestamp();
            
            while (batch_size < 1000) { // Process up to 1000 ops per batch
                const header = self.queue.dequeue() orelse break;
                
                // Handle shutdown signal
                if (header.op_type == SABQueue.OP_SHUTDOWN) {
                    std.log.info("SAB worker received shutdown signal", .{});
                    return;
                }
                
                self.processOperation(db, header) catch |err| {
                    std.log.err("SAB worker failed to process operation: {}", .{err});
                    continue;
                };
                
                batch_size += 1;
                operations_processed += 1;
            }
            
            if (batch_size > 0) {
                batch_count += 1;
                const batch_time = std.time.nanoTimestamp() - batch_start;
                
                // Log performance stats occasionally
                if (batch_count % 1000 == 0) {
                    const avg_batch_time = @as(f64, @floatFromInt(batch_time)) / 1_000_000.0; // Convert to ms
                    const ops_per_sec = @as(f64, @floatFromInt(batch_size)) / (@as(f64, @floatFromInt(batch_time)) / 1_000_000_000.0);
                    
                    std.log.info("SAB worker stats: {} ops processed, batch {} (size: {}, time: {d:.2}ms, {d:.0} ops/sec)", 
                        .{ operations_processed, batch_count, batch_size, avg_batch_time, ops_per_sec });
                }
            } else {
                // No operations available, sleep briefly
                std.time.sleep(1_000_000); // 1ms
            }
        }
        
        std.log.info("SAB worker thread stopped. Processed {} operations in {} batches", 
            .{ operations_processed, batch_count });
    }
    
    fn processOperation(self: *SABWorker, db: *anyopaque, header: SABQueue.OperationHeader) !void {
        const ElkynDB = @import("../embedded_main.zig").ElkynDB;
        const elkyn_db = @as(*ElkynDB, @ptrCast(@alignCast(db)));
        
        // Get path string
        const path_bytes = self.queue.getPath(header);
        const path = try self.allocator.dupe(u8, path_bytes);
        defer self.allocator.free(path);
        
        switch (header.op_type) {
            SABQueue.OP_SET => {
                // Get value data
                const value_bytes = self.queue.getValue(header) orelse return error.MissingValue;
                
                // Parse value based on first byte (simple type detection)
                var value = try self.parseValue(value_bytes);
                defer value.deinit(self.allocator);
                
                // Store in database
                try elkyn_db.set(path, value, null);
            },
            
            SABQueue.OP_DELETE => {
                // Delete from database
                try elkyn_db.delete(path, null);
            },
            
            else => {
                std.log.warn("SAB worker: unknown operation type {}", .{header.op_type});
            },
        }
    }
    
    fn parseValue(self: *SABWorker, data: []const u8) !Value {
        if (data.len == 0) return Value{ .null = {} };
        
        // Simple value type detection based on first byte
        switch (data[0]) {
            's' => {
                // String value
                if (data.len < 2) return error.InvalidString;
                const str = try self.allocator.dupe(u8, data[1..]);
                return Value{ .string = str };
            },
            'n' => {
                // Number value
                if (data.len != 9) return error.InvalidNumber;
                var num: f64 = undefined;
                @memcpy(std.mem.asBytes(&num), data[1..9]);
                return Value{ .number = num };
            },
            'b' => {
                // Boolean value
                if (data.len != 2) return error.InvalidBoolean;
                return Value{ .boolean = data[1] != 0 };
            },
            'z' => {
                // Null value
                return Value{ .null = {} };
            },
            'j' => {
                // JSON object/array (fallback for complex types)
                if (data.len < 2) return error.InvalidJSON;
                const json_str = data[1..];
                return try Value.fromJson(self.allocator, json_str);
            },
            else => {
                std.log.warn("SAB worker: unknown value type marker '{c}'", .{data[0]});
                return error.UnknownValueType;
            },
        }
    }
};