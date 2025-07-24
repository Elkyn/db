const std = @import("std");

pub fn main() !void {
    var mutex = std.Thread.Mutex{};
    var cond = std.Thread.Condition{};
    var ready = false;
    
    const worker = try std.Thread.spawn(.{}, workerThread, .{&mutex, &cond, &ready});
    
    std.time.sleep(100_000_000); // 100ms
    
    mutex.lock();
    ready = true;
    cond.signal();
    mutex.unlock();
    
    worker.join();
    
    std.debug.print("Test completed successfully\n", .{});
}

fn workerThread(mutex: *std.Thread.Mutex, cond: *std.Thread.Condition, ready: *bool) void {
    std.debug.print("Worker: Waiting for signal...\n", .{});
    
    mutex.lock();
    while (!ready.*) {
        cond.wait(mutex);
    }
    mutex.unlock();
    
    std.debug.print("Worker: Received signal!\n", .{});
}