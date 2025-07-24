const std = @import("std");
const SimpleHttpServer = @import("api/simple_http_server.zig").SimpleHttpServer;
const Storage = @import("storage/storage.zig").Storage;
const EventEmitter = @import("storage/event_emitter.zig").EventEmitter;
const EventListener = @import("storage/event_emitter.zig").EventListener;
const Value = @import("storage/value.zig").Value;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    const port: u16 = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else 8080;
    const data_dir = if (args.len > 2) args[2] else "./data";
    
    // Create data directory
    std.fs.cwd().makePath(data_dir) catch {};
    
    std.debug.print("Starting simple HTTP server on port {d} with data dir: {s}\n", .{port, data_dir});
    
    // Initialize storage
    var storage = try Storage.init(allocator, data_dir);
    defer storage.deinit();
    
    // Create event emitter
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    // Set event emitter on storage
    storage.setEventEmitter(&event_emitter);
    
    // Create and start server
    var server = try SimpleHttpServer.init(allocator, &storage, port);
    defer server.deinit();
    
    // Subscribe to all events for SSE
    const sse_subscription_id = try event_emitter.subscribe(
        "/", // Watch root path
        struct {
            fn onEvent(event: @import("storage/event_emitter.zig").Event, context: ?*anyopaque) void {
                std.debug.print("SSE listener received event: type={}, path={s}\n", .{event.type, event.path});
                const srv = @as(*SimpleHttpServer, @ptrCast(@alignCast(context.?)));
                // Forward event to SSE manager
                srv.sse_manager.notifyValueChanged(event.path, event.value) catch |err| {
                    std.log.err("Failed to notify SSE clients: {}", .{err});
                };
            }
        }.onEvent,
        &server,
        true, // Include children
    );
    _ = sse_subscription_id;
    
    try server.start();
}