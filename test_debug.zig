const std = @import("std");

pub fn main() !void {
    _ = std.heap.page_allocator;
    
    // Test basic mutex and condition variable
    var mutex = std.Thread.Mutex{};
    var cond = std.Thread.Condition{};
    
    const worker = try std.Thread.spawn(.{}, workerThread, .{&mutex, &cond});
    
    std.time.sleep(100_000_000); // 100ms
    
    mutex.lock();
    defer mutex.unlock();
    cond.signal();
    
    worker.join();
    
    std.debug.print("Test completed successfully\n", .{});
}

fn workerThread(mutex: *std.Thread.Mutex, cond: *std.Thread.Condition) void {
    std.debug.print("Worker: Waiting for signal...\n", .{});
    
    mutex.lock();
    defer mutex.unlock();
    
    cond.wait(mutex);
    
    std.debug.print("Worker: Received signal!\n", .{});
}