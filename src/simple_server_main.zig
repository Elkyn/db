const std = @import("std");
const ThreadPoolHttpServer = @import("api/thread_pool_server.zig").ThreadPoolHttpServer;
const Storage = @import("storage/storage.zig").Storage;
const EventEmitter = @import("storage/event_emitter.zig").EventEmitter;
const EventListener = @import("storage/event_emitter.zig").EventListener;
const Value = @import("storage/value.zig").Value;
const constants = @import("constants.zig");

const log = std.log.scoped(.server_main);

const usage =
    \\Usage: simple_server [port] [data_dir] [auth_secret] [require|optional] [--allow-token-generation] [--threads=N]
    \\
    \\  port:                    Server port (default: {d})
    \\  data_dir:                Data directory (default: {s})
    \\  auth_secret:             JWT secret for authentication (optional)
    \\  require|optional:        Whether authentication is required (default: optional)
    \\  --allow-token-generation: Allow open token generation (INSECURE - development only)
    \\  --threads=N:             Number of worker threads (default: 4)
    \\
;

pub fn main() !void {
    // Start total boot time measurement
    var boot_timer = try std.time.Timer.start();
    var component_timer = try std.time.Timer.start();
    
    // Track individual component times
    var allocator_time: u64 = 0;
    var args_time: u64 = 0;
    var storage_time: u64 = 0;
    var event_emitter_time: u64 = 0;
    var server_init_time: u64 = 0;
    var auth_time: u64 = 0;
    var subscription_time: u64 = 0;
    
    // Initialize allocator
    component_timer.reset();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    allocator_time = component_timer.read();
    
    // Parse arguments
    component_timer.reset();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    args_time = component_timer.read();
    
    // Check for help flag
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print(usage, .{constants.DEFAULT_SERVER_PORT, constants.DEFAULT_DATA_DIR});
            return;
        }
    }
    
    // Parse arguments more robustly
    var port: u16 = constants.DEFAULT_SERVER_PORT;
    var data_dir: []const u8 = constants.DEFAULT_DATA_DIR;
    var auth_secret: ?[]const u8 = null;
    var require_auth = false;
    var allow_token_generation = false;
    var num_threads: ?usize = null;
    
    // Parse positional arguments (skipping flags)
    var positional_args = std.ArrayList([]const u8).init(allocator);
    defer positional_args.deinit();
    
    for (args[1..]) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            try positional_args.append(arg);
        } else if (std.mem.eql(u8, arg, "--allow-token-generation")) {
            allow_token_generation = true;
        } else if (std.mem.startsWith(u8, arg, "--threads=")) {
            const threads_str = arg["--threads=".len..];
            num_threads = std.fmt.parseInt(usize, threads_str, 10) catch {
                log.err("Invalid thread count: {s}\n", .{threads_str});
                std.debug.print(usage, .{constants.DEFAULT_SERVER_PORT, constants.DEFAULT_DATA_DIR});
                return error.InvalidArgument;
            };
        }
    }
    
    // Process positional arguments
    if (positional_args.items.len > 0) {
        port = std.fmt.parseInt(u16, positional_args.items[0], 10) catch {
            log.err("Invalid port number: {s}\n", .{positional_args.items[0]});
            std.debug.print(usage, .{constants.DEFAULT_SERVER_PORT, constants.DEFAULT_DATA_DIR});
            return error.InvalidArgument;
        };
    }
    if (positional_args.items.len > 1) {
        data_dir = positional_args.items[1];
    }
    if (positional_args.items.len > 2) {
        auth_secret = positional_args.items[2];
    }
    if (positional_args.items.len > 3) {
        if (std.mem.eql(u8, positional_args.items[3], "require")) {
            require_auth = true;
        } else if (!std.mem.eql(u8, positional_args.items[3], "optional")) {
            log.err("Invalid auth mode: {s} (expected 'require' or 'optional')\n", .{positional_args.items[3]});
            return error.InvalidArgument;
        }
    }
    
    std.debug.print("Args count: {d}\n", .{args.len});
    for (args, 0..) |arg, i| {
        std.debug.print("  args[{d}] = {s}\n", .{i, arg});
    }
    
    // Create data directory
    component_timer.reset();
    std.fs.cwd().makePath(data_dir) catch {};
    const dir_creation_time = component_timer.read();
    
    std.debug.print("Starting thread pool HTTP server on port {d} with data dir: {s}\n", .{port, data_dir});
    std.debug.print("Worker threads: {}\n", .{num_threads orelse 4});
    if (auth_secret) |secret| {
        std.debug.print("Authentication enabled (required: {})\n", .{require_auth});
        if (allow_token_generation) {
            std.debug.print("\n⚠️  WARNING: Open token generation is ENABLED!\n", .{});
            std.debug.print("⚠️  This allows anyone to create authentication tokens.\n", .{});
            std.debug.print("⚠️  This should ONLY be used for development!\n\n", .{});
        }
        _ = secret;
    }
    
    // Initialize storage
    component_timer.reset();
    var storage = try Storage.init(allocator, data_dir);
    defer storage.deinit();
    storage_time = component_timer.read();
    
    // Create event emitter
    component_timer.reset();
    var event_emitter = EventEmitter.init(allocator);
    defer event_emitter.deinit();
    
    // Set event emitter on storage
    storage.setEventEmitter(&event_emitter);
    event_emitter_time = component_timer.read();
    
    // Create and start server with thread pool
    component_timer.reset();
    var server = try ThreadPoolHttpServer.init(allocator, &storage, port, num_threads);
    defer server.deinit();
    server_init_time = component_timer.read();
    
    // Set event emitter on server
    server.setEventEmitter(&event_emitter);
    
    // Enable authentication if secret provided
    if (auth_secret) |secret| {
        component_timer.reset();
        try server.enableAuth(secret, require_auth);
        
        // Set token generation permission
        server.setAllowTokenGeneration(allow_token_generation);
        
        // Also enable default security rules when auth is enabled
        const DEFAULT_RULES = @import("rules/engine.zig").DEFAULT_RULES;
        try server.enableRules(DEFAULT_RULES);
        auth_time = component_timer.read();
    }
    
    // Subscribe to all events for SSE
    component_timer.reset();
    const sse_subscription_id = try event_emitter.subscribe(
        "/", // Watch root path
        struct {
            fn onEvent(event: @import("storage/event_emitter.zig").Event, context: ?*anyopaque) void {
                std.debug.print("SSE listener received event: type={}, path={s}\n", .{event.type, event.path});
                const srv = @as(*ThreadPoolHttpServer, @ptrCast(@alignCast(context.?)));
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
    subscription_time = component_timer.read();
    
    // Calculate total boot time
    const total_boot_time = boot_timer.read();
    
    // Print boot time report
    std.debug.print("\n=== Boot Time Report ===\n", .{});
    std.debug.print("Total boot time: {d:.3}ms\n", .{@as(f64, @floatFromInt(total_boot_time)) / 1_000_000.0});
    std.debug.print("\nComponent initialization times:\n", .{});
    std.debug.print("  Allocator setup:    {d:.3}ms\n", .{@as(f64, @floatFromInt(allocator_time)) / 1_000_000.0});
    std.debug.print("  Args parsing:       {d:.3}ms\n", .{@as(f64, @floatFromInt(args_time)) / 1_000_000.0});
    std.debug.print("  Directory creation: {d:.3}ms\n", .{@as(f64, @floatFromInt(dir_creation_time)) / 1_000_000.0});
    std.debug.print("  Storage (LMDB):     {d:.3}ms\n", .{@as(f64, @floatFromInt(storage_time)) / 1_000_000.0});
    std.debug.print("  Event emitter:      {d:.3}ms\n", .{@as(f64, @floatFromInt(event_emitter_time)) / 1_000_000.0});
    std.debug.print("  Server init:        {d:.3}ms\n", .{@as(f64, @floatFromInt(server_init_time)) / 1_000_000.0});
    if (auth_secret != null) {
        std.debug.print("  Auth & rules setup: {d:.3}ms\n", .{@as(f64, @floatFromInt(auth_time)) / 1_000_000.0});
    }
    std.debug.print("  SSE subscription:   {d:.3}ms\n", .{@as(f64, @floatFromInt(subscription_time)) / 1_000_000.0});
    
    // Check if we meet the sub-500ms goal
    const boot_time_ms = @as(f64, @floatFromInt(total_boot_time)) / 1_000_000.0;
    if (boot_time_ms < constants.BOOT_TIME_TARGET_MS) {
        std.debug.print("\n✅ Boot time goal achieved! ({d:.3}ms < {d}ms)\n", .{boot_time_ms, constants.BOOT_TIME_TARGET_MS});
    } else {
        std.debug.print("\n⚠️  Boot time exceeds {d}ms goal! ({d:.3}ms > {d}ms)\n", .{constants.BOOT_TIME_TARGET_MS, boot_time_ms, constants.BOOT_TIME_TARGET_MS});
    }
    std.debug.print("========================\n\n", .{});
    
    try server.start();
}