const std = @import("std");
const ThreadPool = @import("src/api/thread_pool.zig").ThreadPool;

var counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

fn testHandler(ctx: *anyopaque) void {
    const id = @as(*u32, @ptrCast(@alignCast(ctx))).*;
    std.debug.print("Handler called with id: {}\n", .{id});
    _ = counter.fetchAdd(1, .monotonic);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Creating thread pool...\n", .{});
    var pool = try ThreadPool.init(allocator, 2);
    defer pool.deinit();
    
    std.debug.print("Thread pool created with {} threads\n", .{pool.num_threads});
    
    // Give threads time to start
    std.time.sleep(100_000_000);
    
    // Submit some tasks
    var ids = [_]u32{1, 2, 3, 4, 5};
    for (&ids) |*id| {
        std.debug.print("Submitting task {}\n", .{id.*});
        try pool.submit(testHandler, id);
    }
    
    // Wait for tasks to complete
    std.time.sleep(500_000_000);
    
    const final_count = counter.load(.monotonic);
    std.debug.print("Tasks completed: {}/5\n", .{final_count});
}