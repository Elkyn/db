const std = @import("std");
const Storage = @import("../src/storage/storage.zig").Storage;
const EventEmitter = @import("../src/storage/event_emitter.zig").EventEmitter;
const Value = @import("../src/storage/value.zig").Value;

const ITERATIONS = 1_000_000;
const WARMUP = 10_000;

fn benchmarkWrites(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📝 Native Write Performance\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    
    var storage = try Storage.init(allocator, "./bench-native-writes");
    defer storage.deinit();
    
    // Warmup
    var i: usize = 0;
    while (i < WARMUP) : (i += 1) {
        const path = try std.fmt.allocPrint(allocator, "/warmup/{d}", .{i});
        defer allocator.free(path);
        const value = Value{ .number = @floatFromInt(i) };
        try storage.set(path, value);
    }
    
    // Small payload benchmark
    {
        const small_value = Value{ .string = "Hello, World!" };
        const start = std.time.milliTimestamp();
        
        i = 0;
        while (i < ITERATIONS) : (i += 1) {
            const path = try std.fmt.allocPrint(allocator, "/bench/{d}", .{i});
            defer allocator.free(path);
            try storage.set(path, small_value);
        }
        
        const elapsed = std.time.milliTimestamp() - start;
        const ops_per_sec = @as(f64, ITERATIONS) / (@as(f64, @floatFromInt(elapsed)) / 1000.0);
        std.debug.print("  Small writes: {d:.0} ops/sec\n", .{ops_per_sec});
    }
    
    // Medium payload benchmark  
    {
        var obj = std.StringHashMap(Value).init(allocator);
        defer obj.deinit();
        try obj.put("name", Value{ .string = "John Doe" });
        try obj.put("age", Value{ .number = 30 });
        try obj.put("email", Value{ .string = "john@example.com" });
        const medium_value = Value{ .object = obj };
        
        const start = std.time.milliTimestamp();
        
        i = 0;
        while (i < ITERATIONS / 10) : (i += 1) { // Less iterations for larger payload
            const path = try std.fmt.allocPrint(allocator, "/bench/medium/{d}", .{i});
            defer allocator.free(path);
            try storage.set(path, medium_value);
        }
        
        const elapsed = std.time.milliTimestamp() - start;
        const ops_per_sec = @as(f64, ITERATIONS / 10) / (@as(f64, @floatFromInt(elapsed)) / 1000.0);
        std.debug.print("  Medium writes: {d:.0} ops/sec\n", .{ops_per_sec});
    }
}

fn benchmarkReads(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📖 Native Read Performance\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    
    var storage = try Storage.init(allocator, "./bench-native-reads");
    defer storage.deinit();
    
    // Pre-populate data
    const test_value = Value{ .string = "Test data for reading" };
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const path = try std.fmt.allocPrint(allocator, "/data/{d}", .{i});
        defer allocator.free(path);
        try storage.set(path, test_value);
    }
    
    // Benchmark reads
    const start = std.time.milliTimestamp();
    
    i = 0;
    while (i < ITERATIONS) : (i += 1) {
        const path = try std.fmt.allocPrint(allocator, "/data/{d}", .{i % 1000});
        defer allocator.free(path);
        
        var value = try storage.get(path);
        value.deinit(allocator);
    }
    
    const elapsed = std.time.milliTimestamp() - start;
    const ops_per_sec = @as(f64, ITERATIONS) / (@as(f64, @floatFromInt(elapsed)) / 1000.0);
    std.debug.print("  Reads: {d:.0} ops/sec\n", .{ops_per_sec});
}

fn benchmarkEvents(allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ Native Event Performance\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    
    var storage = try Storage.init(allocator, "./bench-native-events");
    defer storage.deinit();
    
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    storage.setEventEmitter(&emitter);
    
    // Event counter
    const Context = struct {
        count: std.atomic.Value(usize),
    };
    var context = Context{ .count = std.atomic.Value(usize).init(0) };
    
    // Subscribe
    _ = try emitter.subscribe("/bench/*", eventCallback, &context, true);
    
    // Benchmark event emission
    const test_value = Value{ .string = "Event test" };
    const start = std.time.milliTimestamp();
    
    var i: usize = 0;
    while (i < 100_000) : (i += 1) { // Less iterations for events
        const path = try std.fmt.allocPrint(allocator, "/bench/{d}", .{i});
        defer allocator.free(path);
        try storage.set(path, test_value);
    }
    
    // Wait for events to be processed
    while (context.count.load(.acquire) < 100_000) {
        std.time.sleep(1_000_000); // 1ms
    }
    
    const elapsed = std.time.milliTimestamp() - start;
    const events_per_sec = @as(f64, 100_000) / (@as(f64, @floatFromInt(elapsed)) / 1000.0);
    std.debug.print("  Events: {d:.0} events/sec\n", .{events_per_sec});
    std.debug.print("  Latency: ~{d:.2} µs/event\n", .{1_000_000.0 / events_per_sec});
}

fn eventCallback(event: @import("../src/storage/event_emitter.zig").Event, context: ?*anyopaque) void {
    _ = event;
    const ctx = @as(*const struct { count: std.atomic.Value(usize) }, @ptrCast(@alignCast(context.?)));
    _ = ctx.count.fetchAdd(1, .release);
}

fn compareWithNodeBridge() !void {
    std.debug.print("\n🌉 Native vs Node.js Bridge Overhead\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    
    std.debug.print("\nTo compare with Node.js bridge:\n", .{});
    std.debug.print("1. Run this native benchmark\n", .{});
    std.debug.print("2. Run: cd bench && npm run bench:ops\n", .{});
    std.debug.print("3. Compare the results\n\n", .{});
    
    std.debug.print("Expected overhead:\n", .{});
    std.debug.print("  - Simple operations: 20-40% (N-API overhead)\n", .{});
    std.debug.print("  - Events: 50-100% (thread synchronization)\n", .{});
    std.debug.print("  - Large payloads: 10-20% (JSON serialization)\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("🚀 Elkyn Native Performance Benchmarks\n", .{});
    std.debug.print("Testing: Writes, Reads, Events\n", .{});
    std.debug.print("Iterations: {d}\n", .{ITERATIONS});
    
    try benchmarkWrites(allocator);
    try benchmarkReads(allocator);
    try benchmarkEvents(allocator);
    try compareWithNodeBridge();
    
    std.debug.print("\n✅ Native benchmarks complete!\n", .{});
}