const std = @import("std");
const testing = std.testing;
const ThreadPool = @import("thread_pool.zig").ThreadPool;

test "thread_pool: basic task execution" {
    const allocator = testing.allocator;
    
    var pool = try ThreadPool.init(allocator, 4);
    defer pool.deinit();
    
    // Simple counter to verify tasks execute
    var counter = std.atomic.Value(u32).init(0);
    
    const Context = struct {
        counter: *std.atomic.Value(u32),
        
        fn increment(ctx: *anyopaque) void {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
            _ = self.counter.fetchAdd(1, .monotonic);
        }
    };
    
    // Submit multiple tasks
    for (0..100) |_| {
        var ctx = Context{ .counter = &counter };
        try pool.submit(.{
            .callback = Context.increment,
            .context = &ctx,
        });
    }
    
    // Wait for tasks to complete
    while (counter.load(.acquire) < 100) {
        std.time.sleep(1 * std.time.ns_per_ms);
    }
    
    try testing.expectEqual(@as(u32, 100), counter.load(.acquire));
}

test "thread_pool: concurrent task execution" {
    const allocator = testing.allocator;
    
    var pool = try ThreadPool.init(allocator, 4);
    defer pool.deinit();
    
    const Context = struct {
        value: u32,
        result: *u32,
        mutex: *std.Thread.Mutex,
        
        fn process(ctx: *anyopaque) void {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
            
            // Simulate some work
            std.time.sleep(1 * std.time.ns_per_ms);
            
            self.mutex.lock();
            defer self.mutex.unlock();
            self.result.* += self.value;
        }
    };
    
    var result: u32 = 0;
    var mutex = std.Thread.Mutex{};
    
    // Submit tasks that sum numbers
    var contexts = try allocator.alloc(Context, 50);
    defer allocator.free(contexts);
    
    for (contexts, 1..) |*ctx, i| {
        ctx.* = .{
            .value = @intCast(i),
            .result = &result,
            .mutex = &mutex,
        };
        
        try pool.submit(.{
            .callback = Context.process,
            .context = ctx,
        });
    }
    
    // Wait for completion
    while (true) {
        mutex.lock();
        const current = result;
        mutex.unlock();
        
        if (current == 1275) break; // Sum of 1..50
        std.time.sleep(10 * std.time.ns_per_ms);
    }
    
    try testing.expectEqual(@as(u32, 1275), result);
}

test "thread_pool: handles empty queue" {
    const allocator = testing.allocator;
    
    var pool = try ThreadPool.init(allocator, 2);
    defer pool.deinit();
    
    // Just let it run with no tasks
    std.time.sleep(10 * std.time.ns_per_ms);
    
    // Should shut down cleanly
}

test "thread_pool: stress test" {
    const allocator = testing.allocator;
    
    var pool = try ThreadPool.init(allocator, 8);
    defer pool.deinit();
    
    var completed = std.atomic.Value(u32).init(0);
    
    const Context = struct {
        counter: *std.atomic.Value(u32),
        
        fn work(ctx: *anyopaque) void {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
            // Simulate variable work
            std.time.sleep(@mod(self.counter.load(.monotonic), 3) * std.time.ns_per_ms);
            _ = self.counter.fetchAdd(1, .monotonic);
        }
    };
    
    // Submit many tasks rapidly
    for (0..1000) |_| {
        var ctx = Context{ .counter = &completed };
        try pool.submit(.{
            .callback = Context.work,
            .context = &ctx,
        });
    }
    
    // Wait for all tasks
    const start = std.time.milliTimestamp();
    while (completed.load(.acquire) < 1000) {
        std.time.sleep(10 * std.time.ns_per_ms);
        
        // Timeout after 5 seconds
        if (std.time.milliTimestamp() - start > 5000) {
            return error.TestTimeout;
        }
    }
    
    try testing.expectEqual(@as(u32, 1000), completed.load(.acquire));
}