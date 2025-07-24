const std = @import("std");
const ThreadPool = @import("thread_pool.zig").ThreadPool;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var pool = try ThreadPool.init(allocator, 2);
    defer pool.deinit();
    
    // Start the thread pool
    try pool.start();
    
    std.debug.print("Thread pool created and started\n", .{});
    
    // Submit one simple task
    const Context = struct {
        fn work(ctx: *anyopaque) void {
            _ = ctx;
            std.debug.print("Task executed!\n", .{});
        }
    };
    
    var dummy: u32 = 42;
    try pool.submit(.{
        .callback = Context.work,
        .context = &dummy,
    });
    
    std.time.sleep(100 * std.time.ns_per_ms);
    
    std.debug.print("Shutting down\n", .{});
}