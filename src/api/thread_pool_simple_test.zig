const std = @import("std");
const testing = std.testing;

test "basic thread pool concepts" {
    // Test basic mutex and condition variable usage
    const TestData = struct {
        mutex: std.Thread.Mutex = .{},
        condition: std.Thread.Condition = .{},
        value: i32 = 0,
        done: bool = false,
    };
    
    var data = TestData{};
    
    const worker = struct {
        fn run(d: *TestData) void {
            d.mutex.lock();
            defer d.mutex.unlock();
            
            d.value = 42;
            d.done = true;
            d.condition.signal();
        }
    }.run;
    
    // Start worker thread
    const thread = try std.Thread.spawn(.{}, worker, .{&data});
    
    // Wait for signal
    data.mutex.lock();
    while (!data.done) {
        data.condition.wait(&data.mutex);
    }
    data.mutex.unlock();
    
    thread.join();
    
    try testing.expectEqual(@as(i32, 42), data.value);
}

test "simple work queue" {
    const Task = struct {
        id: i32,
        processed: bool = false,
    };
    
    const Queue = struct {
        tasks: std.ArrayList(Task),
        mutex: std.Thread.Mutex = .{},
        
        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .tasks = std.ArrayList(Task).init(allocator),
            };
        }
        
        fn deinit(self: *@This()) void {
            self.tasks.deinit();
        }
        
        fn push(self: *@This(), task: Task) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.tasks.append(task);
        }
        
        fn pop(self: *@This()) ?Task {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.tasks.items.len == 0) return null;
            return self.tasks.orderedRemove(0);
        }
    };
    
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();
    
    // Add tasks
    try queue.push(.{ .id = 1 });
    try queue.push(.{ .id = 2 });
    
    // Process tasks
    var processed_count: i32 = 0;
    while (queue.pop()) |task| {
        processed_count += 1;
        try testing.expect(task.id == processed_count);
    }
    
    try testing.expectEqual(@as(i32, 2), processed_count);
}