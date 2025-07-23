const std = @import("std");
const storage_mod = @import("storage/storage.zig");
const event_emitter_mod = @import("storage/event_emitter.zig");
const http_server_mod = @import("api/http_server.zig");

const Storage = storage_mod.Storage;
const EventEmitter = event_emitter_mod.EventEmitter;
const HttpServer = http_server_mod.HttpServer;

const log = std.log.scoped(.main);

pub fn main() !void {
    // Start timer for boot time measurement
    var timer = try std.time.Timer.start();
    
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var port: u16 = 9000;
    var data_dir: []const u8 = "./data";
    
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port = try std.fmt.parseInt(u16, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--data") and i + 1 < args.len) {
            data_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            try printUsage();
            return;
        }
    }

    // Initialize storage
    log.info("Initializing Elkyn DB...", .{});
    
    // Create data directory if it doesn't exist
    const abs_data_dir = if (std.fs.path.isAbsolute(data_dir))
        data_dir
    else blk: {
        const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(cwd);
        break :blk try std.fs.path.join(allocator, &.{ cwd, data_dir });
    };
    defer if (!std.fs.path.isAbsolute(data_dir)) allocator.free(abs_data_dir);
    
    std.fs.makeDirAbsolute(abs_data_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    
    // Initialize storage with LMDB backend
    var db_storage = try Storage.init(allocator, abs_data_dir);
    defer db_storage.deinit();
    
    // Initialize event emitter for real-time updates
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    // Connect event emitter to storage
    db_storage.setEventEmitter(&emitter);
    
    const boot_time = timer.read();
    log.info("Elkyn DB started in {d}ms on port {d}", .{ boot_time / 1_000_000, port });
    log.info("Data directory: {s}", .{data_dir});
    log.info("Storage backend: LMDB", .{});
    log.info("Real-time events: Enabled", .{});
    
    // Initialize HTTP server
    var http_server = try HttpServer.init(allocator, &db_storage, &emitter, port);
    defer http_server.deinit();
    
    // Set up signal handler for graceful shutdown
    const sig_action = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &sig_action, null);
    
    // Start HTTP server in a separate thread
    const server_thread = try std.Thread.spawn(.{}, startHttpServer, .{ &http_server, &should_quit });
    defer server_thread.join();
    
    log.info("Press Ctrl+C to stop", .{});
    
    // Keep running until signal
    while (!should_quit.load(.acquire)) {
        std.time.sleep(100 * std.time.ns_per_ms);
    }
    
    log.info("Shutting down gracefully...", .{});
}

var should_quit = std.atomic.Value(bool).init(false);

fn handleSignal(sig: c_int) callconv(.C) void {
    _ = sig;
    should_quit.store(true, .release);
}

fn startHttpServer(server: *HttpServer, quit_signal: *const std.atomic.Value(bool)) !void {
    server.start(quit_signal) catch |err| {
        if (quit_signal.load(.acquire)) {
            // Normal shutdown
            return;
        }
        log.err("HTTP server error: {}", .{err});
        return err;
    };
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Elkyn DB - Real-time tree database
        \\
        \\Usage: elkyn-db [options]
        \\
        \\Options:
        \\  --port <port>    Port to listen on (default: 9000)
        \\  --data <dir>     Data directory (default: ./data)
        \\  -h, --help       Show this help message
        \\
    , .{});
}