const std = @import("std");
const testing = std.testing;
const storage_mod = @import("storage.zig");
const value_mod = @import("value.zig");
const event_emitter_mod = @import("event_emitter.zig");

const Storage = storage_mod.Storage;
const Value = value_mod.Value;
const EventEmitter = event_emitter_mod.EventEmitter;
const Event = event_emitter_mod.Event;
const EventType = event_emitter_mod.EventType;

fn setupTestStorage(allocator: std.mem.Allocator) !struct { storage: Storage, dir: []const u8 } {
    const nanos = std.time.nanoTimestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_storage_events_test_{d}", .{nanos});
    try std.fs.makeDirAbsolute(test_dir);

    const storage = try Storage.init(allocator, test_dir);
    return .{ .storage = storage, .dir = test_dir };
}

fn cleanupTestDir(path: []const u8) void {
    std.fs.deleteTreeAbsolute(path) catch |err| {
        std.log.warn("Failed to cleanup test directory {s}: {}", .{ path, err });
    };
}

// Test context for capturing events
const TestContext = struct {
    events: std.ArrayList(Event),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) TestContext {
        return .{
            .events = std.ArrayList(Event).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *TestContext) void {
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.deinit();
    }
};

fn testListener(event: Event, context: ?*anyopaque) void {
    const ctx = @as(*TestContext, @ptrCast(@alignCast(context.?)));
    
    // Clone the event for storage
    const event_copy = Event{
        .type = event.type,
        .path = ctx.allocator.dupe(u8, event.path) catch unreachable,
        .value = if (event.value) |v| v.clone(ctx.allocator) catch unreachable else null,
        .previous_value = if (event.previous_value) |v| v.clone(ctx.allocator) catch unreachable else null,
        .key = if (event.key) |k| ctx.allocator.dupe(u8, k) catch unreachable else null,
    };
    
    ctx.events.append(event_copy) catch unreachable;
}

test "Storage with Events: set triggers value_changed" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create event emitter and context
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe to all changes
    const sub_id = try emitter.subscribe("/", testListener, &ctx, true);
    defer emitter.unsubscribe(sub_id);

    // Connect emitter to storage
    storage.setEventEmitter(&emitter);

    // Set a value
    try storage.set("/test", Value{ .string = "hello" });

    // Verify event was emitted
    try testing.expectEqual(@as(usize, 1), ctx.events.items.len);
    try testing.expectEqual(EventType.value_changed, ctx.events.items[0].type);
    try testing.expectEqualStrings("/test", ctx.events.items[0].path);
    try testing.expect(ctx.events.items[0].value != null);
    try testing.expect(ctx.events.items[0].previous_value == null);
}

test "Storage with Events: update triggers value_changed with previous" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create event emitter and context
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe to all changes
    const sub_id = try emitter.subscribe("/", testListener, &ctx, true);
    defer emitter.unsubscribe(sub_id);

    // Connect emitter to storage
    storage.setEventEmitter(&emitter);

    // Set initial value
    try storage.set("/test", Value{ .string = "initial" });
    
    // Clear events
    for (ctx.events.items) |*event| {
        event.deinit(allocator);
    }
    ctx.events.clearRetainingCapacity();

    // Update value
    try storage.set("/test", Value{ .string = "updated" });

    // Verify event was emitted with previous value
    try testing.expectEqual(@as(usize, 1), ctx.events.items.len);
    try testing.expectEqual(EventType.value_changed, ctx.events.items[0].type);
    try testing.expect(ctx.events.items[0].value != null);
    try testing.expect(ctx.events.items[0].previous_value != null);
    try testing.expectEqualStrings("updated", ctx.events.items[0].value.?.string);
    try testing.expectEqualStrings("initial", ctx.events.items[0].previous_value.?.string);
}

test "Storage with Events: delete triggers value_deleted" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create event emitter and context
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe to all changes
    const sub_id = try emitter.subscribe("/", testListener, &ctx, true);
    defer emitter.unsubscribe(sub_id);

    // Connect emitter to storage
    storage.setEventEmitter(&emitter);

    // Set a value
    try storage.set("/test", Value{ .string = "to_delete" });
    
    // Clear events
    for (ctx.events.items) |*event| {
        event.deinit(allocator);
    }
    ctx.events.clearRetainingCapacity();

    // Delete the value
    try storage.delete("/test");

    // Verify delete event was emitted
    try testing.expectEqual(@as(usize, 1), ctx.events.items.len);
    try testing.expectEqual(EventType.value_deleted, ctx.events.items[0].type);
    try testing.expectEqualStrings("/test", ctx.events.items[0].path);
    try testing.expect(ctx.events.items[0].value == null);
    try testing.expect(ctx.events.items[0].previous_value != null);
    try testing.expectEqualStrings("to_delete", ctx.events.items[0].previous_value.?.string);
}

test "Storage with Events: nested object set emits multiple events" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Create event emitter and context
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe to /user path and children
    const sub_id = try emitter.subscribe("/user", testListener, &ctx, true);
    defer emitter.unsubscribe(sub_id);

    // Connect emitter to storage
    storage.setEventEmitter(&emitter);

    // Create nested object
    var user = std.StringHashMap(Value).init(allocator);
    try user.put(try allocator.dupe(u8, "name"), Value{ .string = try allocator.dupe(u8, "Alice") });
    try user.put(try allocator.dupe(u8, "age"), Value{ .number = 30 });

    var user_value = Value{ .object = user };
    defer user_value.deinit(allocator);

    // Set nested object (this will expand into multiple paths)
    try storage.set("/user", user_value);

    // Should get one event for the /user path
    try testing.expectEqual(@as(usize, 1), ctx.events.items.len);
    try testing.expectEqualStrings("/user", ctx.events.items[0].path);
}

test "Storage with Events: no emitter means no events" {
    const allocator = testing.allocator;
    const result = try setupTestStorage(allocator);
    defer allocator.free(result.dir);
    defer cleanupTestDir(result.dir);
    var storage = result.storage;
    defer storage.deinit();

    // Don't set an event emitter

    // Operations should work without errors
    try storage.set("/test", Value{ .string = "hello" });
    try storage.delete("/test");
    
    // No events emitted, but no errors either
    try testing.expect(true);
}