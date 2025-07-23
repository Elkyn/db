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

// Test listener that just counts events
var event_count: usize = 0;
var last_event_type: ?EventType = null;

fn simpleListener(event: Event, context: ?*anyopaque) void {
    _ = context;
    event_count += 1;
    last_event_type = event.type;
}

test "Simple Events: basic set triggers event" {
    const allocator = testing.allocator;
    
    // Reset counters
    event_count = 0;
    last_event_type = null;
    
    // Create unique test directory
    const nanos = std.time.nanoTimestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_simple_test_{d}", .{nanos});
    defer allocator.free(test_dir);
    
    try std.fs.makeDirAbsolute(test_dir);
    defer std.fs.deleteTreeAbsolute(test_dir) catch {};
    
    // Create storage
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    // Create event emitter
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    // Subscribe to root
    const sub_id = try emitter.subscribe("/", simpleListener, null, true);
    defer emitter.unsubscribe(sub_id);
    
    // Connect emitter to storage
    storage.setEventEmitter(&emitter);
    
    // Set a simple string value
    try storage.set("/test", Value{ .string = "hello" });
    
    // Verify event was triggered
    try testing.expectEqual(@as(usize, 1), event_count);
    try testing.expectEqual(EventType.value_changed, last_event_type.?);
}

test "Simple Events: update with previous value" {
    const allocator = testing.allocator;
    
    // Reset counters
    event_count = 0;
    last_event_type = null;
    
    // Create unique test directory
    const nanos = std.time.nanoTimestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_simple_test2_{d}", .{nanos});
    defer allocator.free(test_dir);
    
    try std.fs.makeDirAbsolute(test_dir);
    defer std.fs.deleteTreeAbsolute(test_dir) catch {};
    
    // Create storage
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    // First set without emitter
    const initial_str = try allocator.dupe(u8, "initial");
    defer allocator.free(initial_str);
    try storage.set("/test", Value{ .string = initial_str });
    
    // Now add emitter
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    const sub_id = try emitter.subscribe("/", simpleListener, null, true);
    defer emitter.unsubscribe(sub_id);
    
    storage.setEventEmitter(&emitter);
    
    // Update the value
    const updated_str = try allocator.dupe(u8, "updated");
    defer allocator.free(updated_str);
    try storage.set("/test", Value{ .string = updated_str });
    
    // Verify event
    try testing.expectEqual(@as(usize, 1), event_count);
    try testing.expectEqual(EventType.value_changed, last_event_type.?);
}

test "Simple Events: set object value" {
    const allocator = testing.allocator;
    
    // Reset counters
    event_count = 0;
    last_event_type = null;
    
    // Create unique test directory
    const nanos = std.time.nanoTimestamp();
    const test_dir = try std.fmt.allocPrint(allocator, "/tmp/elkyn_simple_test3_{d}", .{nanos});
    defer allocator.free(test_dir);
    
    try std.fs.makeDirAbsolute(test_dir);
    defer std.fs.deleteTreeAbsolute(test_dir) catch {};
    
    // Create storage
    var storage = try Storage.init(allocator, test_dir);
    defer storage.deinit();
    
    // Create event emitter
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();
    
    const sub_id = try emitter.subscribe("/", simpleListener, null, true);
    defer emitter.unsubscribe(sub_id);
    
    storage.setEventEmitter(&emitter);
    
    // Create a simple object
    var obj = std.StringHashMap(Value).init(allocator);
    try obj.put(try allocator.dupe(u8, "name"), Value{ .string = try allocator.dupe(u8, "test") });
    
    var obj_value = Value{ .object = obj };
    defer obj_value.deinit(allocator);
    
    // Set object
    try storage.set("/user", obj_value);
    
    // Should get one event for the set operation
    try testing.expectEqual(@as(usize, 1), event_count);
}