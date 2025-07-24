const std = @import("std");
const Storage = @import("../storage/storage.zig").Storage;
const ThreadPoolHttpServer = @import("thread_pool_server.zig").ThreadPoolHttpServer;

/// Example of using the thread pool HTTP server
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize storage
    var storage = try Storage.init(allocator, "data");
    defer storage.deinit();

    // Create server with 8 worker threads
    var server = try ThreadPoolHttpServer.init(allocator, &storage, 3000, 8);
    defer server.deinit();

    // Optional: Enable authentication
    // try server.enableAuth("your-secret-key", true);

    // Optional: Enable security rules
    // const rules = 
    //     \\{
    //     \\  "rules": {
    //     \\    "/public": {
    //     \\      ".read": true,
    //     \\      ".write": false
    //     \\    },
    //     \\    "/users/$uid": {
    //     \\      ".read": "$uid === auth.uid",
    //     \\      ".write": "$uid === auth.uid"
    //     \\    }
    //     \\  }
    //     \\}
    // ;
    // try server.enableRules(rules);

    // Start server (blocks forever)
    try server.start();
}