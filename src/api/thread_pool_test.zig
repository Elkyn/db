const std = @import("std");
const testing = std.testing;
const ThreadPool = @import("thread_pool.zig").ThreadPool;
const WorkQueue = @import("thread_pool.zig").WorkQueue;

test "thread pool: basic initialization and shutdown" {
    var pool = try ThreadPool.init(testing.allocator, 2);
    defer pool.deinit();
    
    try testing.expectEqual(@as(usize, 2), pool.num_threads);
}

test "thread pool: submit and execute tasks" {
    var pool = try ThreadPool.init(testing.allocator, 2);
    defer pool.deinit();
    
    // Counter protected by mutex
    const Counter = struct {
        value: i32,
        mutex: std.Thread.Mutex,
    };
    
    var counter = Counter{ .value = 0, .mutex = .{} };
    
    const increment = struct {
        fn run(ctx: *anyopaque) void {
            const c = @as(*Counter, @ptrCast(@alignCast(ctx)));
            c.mutex.lock();
            defer c.mutex.unlock();
            c.value += 1;
        }
    }.run;
    
    // Submit multiple tasks
    const num_tasks = 10;
    for (0..num_tasks) |_| {
        try pool.submit(increment, &counter);
    }
    
    // Wait a bit for tasks to complete
    std.time.sleep(100 * std.time.ns_per_ms);
    
    counter.mutex.lock();
    defer counter.mutex.unlock();
    try testing.expectEqual(@as(i32, num_tasks), counter.value);
}

test "work queue: enqueue and dequeue" {
    var queue = WorkQueue.init(testing.allocator);
    defer queue.deinit();
    
    var executed = false;
    
    const handler = struct {
        fn run(ctx: *anyopaque) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx)));
            flag.* = true;
        }
    }.run;
    
    // Enqueue a task
    try queue.enqueue(handler, &executed);
    
    // Dequeue and execute
    if (queue.dequeue()) |task| {
        task.handler(task.context);
    }
    
    try testing.expect(executed);
}

test "work queue: shutdown behavior" {
    var queue = WorkQueue.init(testing.allocator);
    defer queue.deinit();
    
    // Start a thread that waits for work
    const worker_thread = try std.Thread.spawn(.{}, struct {
        fn run(q: *WorkQueue) void {
            _ = q.dequeue(); // Should return null after shutdown
        }
    }.run, .{&queue});
    
    // Give thread time to start waiting
    std.time.sleep(10 * std.time.ns_per_ms);
    
    // Shutdown should wake the thread
    queue.setShutdown();
    worker_thread.join();
    
    // Further enqueues should fail
    const dummy = struct {
        fn run(_: *anyopaque) void {}
    }.run;
    
    const result = queue.enqueue(dummy, undefined);
    try testing.expectError(error.QueueShutdown, result);
}

test "thread pool: concurrent task execution" {
    var pool = try ThreadPool.init(testing.allocator, 4);
    defer pool.deinit();
    
    // Shared data structure
    const SharedData = struct {
        values: [100]i32,
        mutex: std.Thread.Mutex,
    };
    
    var data = SharedData{ 
        .values = [_]i32{0} ** 100,
        .mutex = .{},
    };
    
    const Context = struct {
        data: *SharedData,
        index: usize,
        value: i32,
    };
    
    const worker = struct {
        fn run(ctx_ptr: *anyopaque) void {
            const ctx = @as(*Context, @ptrCast(@alignCast(ctx_ptr)));
            
            ctx.data.mutex.lock();
            defer ctx.data.mutex.unlock();
            
            ctx.data.values[ctx.index] = ctx.value;
        }
    }.run;
    
    // Submit tasks to set array values
    var contexts: [100]Context = undefined;
    for (&contexts, 0..) |*ctx, i| {
        ctx.* = .{
            .data = &data,
            .index = i,
            .value = @as(i32, @intCast(i + 1)),
        };
        try pool.submit(worker, ctx);
    }
    
    // Wait for completion
    std.time.sleep(100 * std.time.ns_per_ms);
    
    // Verify all values were set
    data.mutex.lock();
    defer data.mutex.unlock();
    
    for (data.values, 0..) |value, i| {
        try testing.expectEqual(@as(i32, @intCast(i + 1)), value);
    }
}