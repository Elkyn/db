const std = @import("std");

/// Create a temporary test directory and return the path
pub fn createTestDir(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_test_{d}_{d}", .{ timestamp, std.crypto.random.int(u32) });
    try std.fs.makeDirAbsolute(test_dir);
    return test_dir;
}

/// Clean up a test directory
pub fn cleanupTestDir(path: []const u8) void {
    std.fs.deleteTreeAbsolute(path) catch |err| {
        std.log.warn("Failed to cleanup test directory {s}: {}", .{ path, err });
    };
}

/// Create an in-memory test path (for tests that don't need persistence)
pub fn getInMemoryPath() []const u8 {
    return ":memory:";
}