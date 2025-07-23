const std = @import("std");

const log = std.log.scoped(.thread_pool);

pub const Task = struct {
    callback: *const fn (*anyopaque) void,
    context: *anyopaque,
};

pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    threads: []std.Thread,
    queue: std.ArrayList(Task),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    should_stop: std.atomic.Value(bool),
    
    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !ThreadPool {
        var pool = ThreadPool{
            .allocator = allocator,
            .threads = try allocator.alloc(std.Thread, thread_count),
            .queue = std.ArrayList(Task).init(allocator),
            .mutex = .{},
            .condition = .{},
            .should_stop = std.atomic.Value(bool).init(false),
        };
        errdefer allocator.free(pool.threads);
        
        // Start worker threads
        for (pool.threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerLoop, .{&pool});
            log.debug("Started worker thread {d}", .{i});
        }
        
        return pool;
    }
    
    pub fn deinit(self: *ThreadPool) void {
        // Signal threads to stop
        self.should_stop.store(true, .release);
        self.condition.broadcast();
        
        // Wait for all threads to finish
        for (self.threads) |thread| {
            thread.join();
        }
        
        // Clean up
        self.allocator.free(self.threads);
        self.queue.deinit();
    }
    
    pub fn submit(self: *ThreadPool, task: Task) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.queue.append(task);
        self.condition.signal();
    }
    
    fn workerLoop(pool: *ThreadPool) void {
        while (!pool.should_stop.load(.acquire)) {
            pool.mutex.lock();
            
            // Wait for work or shutdown signal
            while (pool.queue.items.len == 0 and !pool.should_stop.load(.acquire)) {
                pool.condition.wait(&pool.mutex);
            }
            
            // Get task if available
            const task = if (pool.queue.items.len > 0) 
                pool.queue.orderedRemove(0)
            else 
                null;
            
            pool.mutex.unlock();
            
            // Execute task outside of lock
            if (task) |t| {
                t.callback(t.context);
            }
        }
    }
};