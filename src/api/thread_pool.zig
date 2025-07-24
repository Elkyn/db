const std = @import("std");
const constants = @import("../constants.zig");

const log = std.log.scoped(.thread_pool);

/// Thread-safe work queue for passing tasks between threads
pub const WorkQueue = struct {
    const Task = struct {
        /// Function pointer to execute
        handler: *const fn (*anyopaque) void,
        /// Context data to pass to handler
        context: *anyopaque,
    };

    allocator: std.mem.Allocator,
    queue: std.ArrayList(Task),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    is_shutdown: bool,

    pub fn init(allocator: std.mem.Allocator) WorkQueue {
        return .{
            .allocator = allocator,
            .queue = std.ArrayList(Task).init(allocator),
            .mutex = .{},
            .condition = .{},
            .is_shutdown = false,
        };
    }

    pub fn deinit(self: *WorkQueue) void {
        self.queue.deinit();
    }

    /// Add a task to the queue
    pub fn enqueue(self: *WorkQueue, handler: *const fn (*anyopaque) void, context: *anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_shutdown) return error.QueueShutdown;

        try self.queue.append(.{
            .handler = handler,
            .context = context,
        });
        
        log.debug("Enqueued task, queue size: {}", .{self.queue.items.len});

        // Wake up one waiting worker
        self.condition.signal();
    }

    /// Get a task from the queue (blocks if empty)
    pub fn dequeue(self: *WorkQueue) ?Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Wait while queue is empty and not shutting down
        while (self.queue.items.len == 0 and !self.is_shutdown) {
            log.debug("Worker waiting, queue empty, shutdown: {}", .{self.is_shutdown});
            self.condition.wait(&self.mutex);
            log.debug("Worker woke up, queue size: {}, shutdown: {}", .{self.queue.items.len, self.is_shutdown});
        }

        if (self.is_shutdown and self.queue.items.len == 0) {
            return null;
        }

        // Get task from front of queue
        const task = self.queue.orderedRemove(0);
        log.debug("Dequeued task, remaining: {}", .{self.queue.items.len});
        return task;
    }

    /// Shutdown the queue and wake all waiting threads
    pub fn setShutdown(self: *WorkQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.is_shutdown = true;
        self.condition.broadcast();
    }
};

/// Thread pool for handling HTTP requests
pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    threads: []std.Thread,
    work_queue: WorkQueue,
    num_threads: usize,

    const DEFAULT_NUM_THREADS = 4;

    pub fn init(allocator: std.mem.Allocator, num_threads: ?usize) !*ThreadPool {
        const thread_count = num_threads orelse DEFAULT_NUM_THREADS;
        
        var pool = try allocator.create(ThreadPool);
        errdefer allocator.destroy(pool);
        
        pool.* = ThreadPool{
            .allocator = allocator,
            .threads = try allocator.alloc(std.Thread, thread_count),
            .work_queue = WorkQueue.init(allocator),
            .num_threads = thread_count,
        };
        errdefer pool.deinit();

        // Start worker threads
        for (pool.threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerLoop, .{ &pool.work_queue, i });
        }

        log.info("Thread pool initialized with {} threads", .{thread_count});
        return pool;
    }

    pub fn deinit(self: *ThreadPool) void {
        // Shutdown work queue
        self.work_queue.setShutdown();

        // Wait for all threads to finish
        for (self.threads) |thread| {
            thread.join();
        }

        self.work_queue.deinit();
        self.allocator.free(self.threads);
        log.info("Thread pool shutdown complete", .{});
    }

    /// Submit a task to the thread pool
    pub fn submit(self: *ThreadPool, handler: *const fn (*anyopaque) void, context: *anyopaque) !void {
        try self.work_queue.enqueue(handler, context);
    }

    /// Worker thread main loop
    fn workerLoop(work_queue: *WorkQueue, thread_id: usize) void {
        log.debug("Worker thread {} started", .{thread_id});
        defer log.debug("Worker thread {} exiting", .{thread_id});

        while (true) {
            const task = work_queue.dequeue() orelse break;
            
            log.debug("Worker thread {} executing task", .{thread_id});
            
            // Execute the task
            task.handler(task.context);
            
            log.debug("Worker thread {} completed task", .{thread_id});
        }
    }
};

/// Context for HTTP request handling in thread pool
pub const RequestContext = struct {
    allocator: std.mem.Allocator,
    connection: std.net.Server.Connection,
    server: *anyopaque, // Pointer to SimpleHttpServer
    
    /// Allocate context on heap since it will be passed between threads
    pub fn create(allocator: std.mem.Allocator, connection: std.net.Server.Connection, server: *anyopaque) !*RequestContext {
        const ctx = try allocator.create(RequestContext);
        ctx.* = .{
            .allocator = allocator,
            .connection = connection,
            .server = server,
        };
        return ctx;
    }
    
    pub fn destroy(self: *RequestContext) void {
        self.allocator.destroy(self);
    }
};