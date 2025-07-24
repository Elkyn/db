const std = @import("std");
const tree = @import("tree.zig");
const value_mod = @import("value.zig");

const Value = value_mod.Value;

/// Event types for database operations
pub const EventType = enum {
    value_changed,
    value_deleted,
    child_added,
    child_changed,
    child_removed,
};

/// Event data structure
pub const Event = struct {
    type: EventType,
    path: []const u8,
    value: ?Value,
    previous_value: ?Value,
    key: ?[]const u8, // For child events, the key of the child

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.value) |*val| {
            val.deinit(allocator);
        }
        if (self.previous_value) |*val| {
            val.deinit(allocator);
        }
        if (self.key) |k| {
            allocator.free(k);
        }
    }
};

/// Subscription filter
pub const Filter = struct {
    // TODO: Add filter predicates
};

/// Listener function type
pub const ListenerFn = *const fn (event: Event, context: ?*anyopaque) void;

/// Subscription handle
pub const Subscription = struct {
    id: u64,
    path_pattern: []const u8,
    listener: ListenerFn,
    context: ?*anyopaque,
    filter: ?Filter,
    include_children: bool,

    pub fn deinit(self: *Subscription, allocator: std.mem.Allocator) void {
        allocator.free(self.path_pattern);
    }
};

/// Thread-safe event emitter with Observable pattern
pub const EventEmitter = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.AutoHashMap(u64, Subscription),
    next_subscription_id: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) EventEmitter {
        return EventEmitter{
            .allocator = allocator,
            .subscriptions = std.AutoHashMap(u64, Subscription).init(allocator),
            .next_subscription_id = std.atomic.Value(u64).init(1),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *EventEmitter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            var sub = entry.value_ptr;
            sub.deinit(self.allocator);
        }
        self.subscriptions.deinit();
    }

    /// Subscribe to events at a specific path pattern
    pub fn subscribe(
        self: *EventEmitter,
        path_pattern: []const u8,
        listener: ListenerFn,
        context: ?*anyopaque,
        include_children: bool,
    ) !u64 {
        const id = self.next_subscription_id.fetchAdd(1, .monotonic);
        
        const pattern_copy = try self.allocator.dupe(u8, path_pattern);
        errdefer self.allocator.free(pattern_copy);

        const subscription = Subscription{
            .id = id,
            .path_pattern = pattern_copy,
            .listener = listener,
            .context = context,
            .filter = null,
            .include_children = include_children,
        };

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.subscriptions.put(id, subscription);
        return id;
    }

    /// Unsubscribe from events
    pub fn unsubscribe(self: *EventEmitter, subscription_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.subscriptions.fetchRemove(subscription_id)) |entry| {
            var sub = entry.value;
            sub.deinit(self.allocator);
        }
    }

    /// Emit an event to all matching subscribers
    pub fn emit(self: *EventEmitter, event: Event) !void {
        std.debug.print("EventEmitter.emit: type={}, path={s}\n", .{event.type, event.path});
        
        // Create a temporary list of matching subscribers to avoid holding lock during callbacks
        var matching = std.ArrayList(struct { listener: ListenerFn, context: ?*anyopaque }).init(self.allocator);
        defer matching.deinit();

        {
            self.mutex.lock();
            defer self.mutex.unlock();

            var iter = self.subscriptions.iterator();
            while (iter.next()) |entry| {
                const sub = entry.value_ptr;
                
                // Check if the event path matches the subscription pattern
                if (try self.pathMatchesSubscription(event.path, sub)) {
                    std.log.debug("EventEmitter: Found matching subscription for path={s}", .{event.path});
                    try matching.append(.{
                        .listener = sub.listener,
                        .context = sub.context,
                    });
                }
            }
        }

        std.log.debug("EventEmitter: Calling {} listeners", .{matching.items.len});
        
        // Call listeners outside of the lock
        for (matching.items) |match| {
            match.listener(event, match.context);
        }
    }

    /// Check if an event path matches a subscription
    fn pathMatchesSubscription(self: *EventEmitter, event_path: []const u8, sub: *const Subscription) !bool {
        // Exact match
        if (std.mem.eql(u8, event_path, sub.path_pattern)) {
            return true;
        }

        // Pattern matching with wildcards
        if (tree.pathMatches(event_path, sub.path_pattern)) {
            return true;
        }

        // Check if this is a child event and subscription includes children
        if (sub.include_children) {
            // Check if event_path is under subscription path
            const normalized_pattern = try tree.normalizePath(self.allocator, sub.path_pattern);
            defer self.allocator.free(normalized_pattern);

            const normalized_event = try tree.normalizePath(self.allocator, event_path);
            defer self.allocator.free(normalized_event);

            // For root subscription ("/"), match everything except root itself
            if (std.mem.eql(u8, normalized_pattern, "/")) {
                return !std.mem.eql(u8, normalized_event, "/");
            }

            // For other paths, check if event is under subscription path
            const prefix = try std.fmt.allocPrint(self.allocator, "{s}/", .{normalized_pattern});
            defer self.allocator.free(prefix);

            return std.mem.startsWith(u8, normalized_event, prefix);
        }

        return false;
    }

    /// Helper to emit value change events
    pub fn emitValueChanged(
        self: *EventEmitter,
        path: []const u8,
        new_value: Value,
        old_value: ?Value,
    ) !void {
        std.debug.print("EventEmitter.emitValueChanged: path={s}\n", .{path});
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        var new_val_copy = try new_value.clone(self.allocator);
        errdefer new_val_copy.deinit(self.allocator);

        var old_val_copy: ?Value = null;
        if (old_value) |ov| {
            old_val_copy = try ov.clone(self.allocator);
        }
        errdefer if (old_val_copy) |*ov| ov.deinit(self.allocator);

        const event = Event{
            .type = .value_changed,
            .path = path_copy,
            .value = new_val_copy,
            .previous_value = old_val_copy,
            .key = null,
        };
        
        // Emit the event - listeners are called synchronously
        try self.emit(event);
        
        // Event data should NOT be cleaned up here - it's a memory leak!
        // TODO: Fix this by making emit take ownership and having listeners copy what they need
    }

    /// Helper to emit delete events
    pub fn emitValueDeleted(
        self: *EventEmitter,
        path: []const u8,
        old_value: ?Value,
    ) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        var old_val_copy: ?Value = null;
        if (old_value) |ov| {
            old_val_copy = try ov.clone(self.allocator);
        }
        errdefer if (old_val_copy) |*ov| ov.deinit(self.allocator);

        const event = Event{
            .type = .value_deleted,
            .path = path_copy,
            .value = null,
            .previous_value = old_val_copy,
            .key = null,
        };

        try self.emit(event);
        
        // Event data should NOT be cleaned up here - it's a memory leak!
        // TODO: Fix this by making emit take ownership and having listeners copy what they need
    }
};