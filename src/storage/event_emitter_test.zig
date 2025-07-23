const std = @import("std");
const testing = std.testing;

// Import modules from the same directory
const tree = @import("tree.zig");
const value_mod = @import("value.zig");
const event_emitter_mod = @import("event_emitter.zig");

const Value = value_mod.Value;
const EventEmitter = event_emitter_mod.EventEmitter;
const Event = event_emitter_mod.Event;
const EventType = event_emitter_mod.EventType;

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

test "EventEmitter: basic subscription and emission" {
    const allocator = testing.allocator;
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();

    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe to a path
    const sub_id = try emitter.subscribe("/users", testListener, &ctx, false);
    defer emitter.unsubscribe(sub_id);

    // Emit an event
    const value = Value{ .string = "Alice" };
    try emitter.emitValueChanged("/users", value, null);

    // Check that event was received
    try testing.expectEqual(@as(usize, 1), ctx.events.items.len);
    try testing.expectEqual(EventType.value_changed, ctx.events.items[0].type);
    try testing.expectEqualStrings("/users", ctx.events.items[0].path);
}

test "EventEmitter: multiple subscriptions" {
    const allocator = testing.allocator;
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();

    var ctx1 = TestContext.init(allocator);
    defer ctx1.deinit();
    var ctx2 = TestContext.init(allocator);
    defer ctx2.deinit();

    // Subscribe to different paths
    const sub1 = try emitter.subscribe("/users", testListener, &ctx1, false);
    defer emitter.unsubscribe(sub1);
    const sub2 = try emitter.subscribe("/posts", testListener, &ctx2, false);
    defer emitter.unsubscribe(sub2);

    // Emit events
    const user_value = Value{ .string = "Alice" };
    const post_value = Value{ .string = "Hello World" };
    
    try emitter.emitValueChanged("/users", user_value, null);
    try emitter.emitValueChanged("/posts", post_value, null);

    // Check that each context received only its event
    try testing.expectEqual(@as(usize, 1), ctx1.events.items.len);
    try testing.expectEqualStrings("/users", ctx1.events.items[0].path);
    
    try testing.expectEqual(@as(usize, 1), ctx2.events.items.len);
    try testing.expectEqualStrings("/posts", ctx2.events.items[0].path);
}

test "EventEmitter: wildcard subscription" {
    const allocator = testing.allocator;
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();

    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe with wildcard
    const sub_id = try emitter.subscribe("/users/*", testListener, &ctx, false);
    defer emitter.unsubscribe(sub_id);

    // Emit events
    const alice = Value{ .string = "Alice" };
    const bob = Value{ .string = "Bob" };
    
    try emitter.emitValueChanged("/users/alice", alice, null);
    try emitter.emitValueChanged("/users/bob", bob, null);
    try emitter.emitValueChanged("/posts/1", alice, null); // Should not match

    // Check that only matching events were received
    try testing.expectEqual(@as(usize, 2), ctx.events.items.len);
    try testing.expectEqualStrings("/users/alice", ctx.events.items[0].path);
    try testing.expectEqualStrings("/users/bob", ctx.events.items[1].path);
}

test "EventEmitter: child subscription" {
    const allocator = testing.allocator;
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();

    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe with include_children
    const sub_id = try emitter.subscribe("/users", testListener, &ctx, true);
    defer emitter.unsubscribe(sub_id);

    // Emit events
    const value = Value{ .string = "test" };
    
    try emitter.emitValueChanged("/users", value, null); // Exact match
    try emitter.emitValueChanged("/users/alice", value, null); // Child
    try emitter.emitValueChanged("/users/alice/profile", value, null); // Deep child
    try emitter.emitValueChanged("/posts/1", value, null); // Should not match

    // Check that parent and children events were received
    try testing.expectEqual(@as(usize, 3), ctx.events.items.len);
}

test "EventEmitter: root subscription with children" {
    const allocator = testing.allocator;
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();

    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe to root with children
    const sub_id = try emitter.subscribe("/", testListener, &ctx, true);
    defer emitter.unsubscribe(sub_id);

    // Emit events
    const value = Value{ .string = "test" };
    
    try emitter.emitValueChanged("/", value, null); // Root itself
    try emitter.emitValueChanged("/users", value, null); // Child
    try emitter.emitValueChanged("/users/alice", value, null); // Deep child

    // Root subscription with children should get all
    try testing.expectEqual(@as(usize, 3), ctx.events.items.len);
}

test "EventEmitter: delete events" {
    const allocator = testing.allocator;
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();

    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    const sub_id = try emitter.subscribe("/users/alice", testListener, &ctx, false);
    defer emitter.unsubscribe(sub_id);

    // Emit delete event
    const old_value = Value{ .string = "Alice" };
    try emitter.emitValueDeleted("/users/alice", old_value);

    // Check delete event
    try testing.expectEqual(@as(usize, 1), ctx.events.items.len);
    try testing.expectEqual(EventType.value_deleted, ctx.events.items[0].type);
    try testing.expect(ctx.events.items[0].value == null);
    try testing.expect(ctx.events.items[0].previous_value != null);
}

test "EventEmitter: unsubscribe" {
    const allocator = testing.allocator;
    var emitter = EventEmitter.init(allocator);
    defer emitter.deinit();

    var ctx = TestContext.init(allocator);
    defer ctx.deinit();

    // Subscribe and then unsubscribe
    const sub_id = try emitter.subscribe("/users", testListener, &ctx, false);
    emitter.unsubscribe(sub_id);

    // Emit event
    const value = Value{ .string = "test" };
    try emitter.emitValueChanged("/users", value, null);

    // Should not receive any events
    try testing.expectEqual(@as(usize, 0), ctx.events.items.len);
}