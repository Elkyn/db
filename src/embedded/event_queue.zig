const std = @import("std");
const Value = @import("../storage/value.zig").Value;

/// Thread-safe ring buffer for events
/// Uses lock-free SPSC (Single Producer Single Consumer) design
pub const EventQueue = struct {
    pub const PopResult = struct {
        type: EventType,
        path: [256]u8,
        path_len: u16,
        value: ?[]const u8,
        sequence: u64,
        timestamp: i64,
    };
    const Event = struct {
        type: EventType,
        path: [256]u8, // Fixed size to avoid allocations
        path_len: u16,
        sequence: u64,
        timestamp: i64,
        value_offset: u32, // Offset into value buffer
        value_len: u32,
    };

    pub const EventType = enum(u8) {
        change = 1,
        delete = 2,
    };

    const QUEUE_SIZE = 1024; // Power of 2 for fast modulo
    const VALUE_BUFFER_SIZE = 1024 * 1024; // 1MB for values

    // Ring buffer for events
    events: [QUEUE_SIZE]Event,
    
    // Separate buffer for variable-length values
    value_buffer: []u8,
    value_write_pos: std.atomic.Value(u32),
    
    // Queue positions (cache-line aligned)
    write_pos: std.atomic.Value(u64) align(64),
    read_pos: std.atomic.Value(u64) align(64),
    
    // Sequence counter for ordering
    sequence: std.atomic.Value(u64),
    
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !EventQueue {
        const value_buffer = try allocator.alloc(u8, VALUE_BUFFER_SIZE);
        
        return EventQueue{
            .events = undefined,
            .value_buffer = value_buffer,
            .value_write_pos = std.atomic.Value(u32).init(0),
            .write_pos = std.atomic.Value(u64).init(0),
            .read_pos = std.atomic.Value(u64).init(0),
            .sequence = std.atomic.Value(u64).init(0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EventQueue) void {
        self.allocator.free(self.value_buffer);
    }

    /// Producer side - called from storage thread
    pub fn push(self: *EventQueue, event_type: EventType, path: []const u8, value: ?Value) !void {
        // Get next write position
        const write_pos = self.write_pos.load(.monotonic);
        const read_pos = self.read_pos.load(.acquire);
        
        // Check if queue is full
        if (write_pos - read_pos >= QUEUE_SIZE) {
            return error.QueueFull;
        }
        
        // Serialize value if present
        var value_offset: u32 = 0;
        var value_len: u32 = 0;
        
        if (value) |v| {
            // Reserve space in value buffer
            const value_json = try v.toJson(self.allocator);
            defer self.allocator.free(value_json);
            
            value_len = @intCast(value_json.len);
            value_offset = self.value_write_pos.fetchAdd(value_len, .monotonic);
            
            // Check for value buffer overflow
            if (value_offset + value_len > VALUE_BUFFER_SIZE) {
                // Reset to beginning (simple strategy)
                value_offset = 0;
                self.value_write_pos.store(value_len, .monotonic);
            }
            
            // Copy value data
            @memcpy(self.value_buffer[value_offset..][0..value_len], value_json);
        }
        
        // Create event
        var event = Event{
            .type = event_type,
            .path = [_]u8{0} ** 256,  // Initialize with zeros
            .path_len = @intCast(@min(path.len, 256)),
            .sequence = self.sequence.fetchAdd(1, .monotonic),
            .timestamp = std.time.milliTimestamp(),
            .value_offset = value_offset,
            .value_len = value_len,
        };
        
        // Copy path
        @memcpy(event.path[0..event.path_len], path[0..event.path_len]);
        
        // Write event to ring buffer
        const index = write_pos & (QUEUE_SIZE - 1);
        self.events[index] = event;
        
        // Update write position (release semantics)
        _ = self.write_pos.fetchAdd(1, .release);
    }

    /// Consumer side - called from Node.js thread
    /// Returns a struct with COPIES of the data to avoid lifetime issues
    pub fn pop(self: *EventQueue) ?PopResult {
        const read_pos = self.read_pos.load(.monotonic);
        const write_pos = self.write_pos.load(.acquire);
        
        // Check if queue is empty
        if (read_pos >= write_pos) {
            return null;
        }
        
        // Read event
        const index = read_pos & (QUEUE_SIZE - 1);
        const event = self.events[index];
        
        // Extract value if present
        const value = if (event.value_len > 0)
            self.value_buffer[event.value_offset..][0..event.value_len]
        else
            null;
        
        // Update read position BEFORE we return (important!)
        _ = self.read_pos.fetchAdd(1, .release);
        
        
        // Return a COPY of the event data
        var result = PopResult{
            .type = event.type,
            .path = [_]u8{0} ** 256,
            .path_len = event.path_len,
            .value = value,
            .sequence = event.sequence,
            .timestamp = event.timestamp,
        };
        
        // Copy the path data
        @memcpy(result.path[0..event.path_len], event.path[0..event.path_len]);
        
        return result;
    }

    /// Batch pop for efficiency
    pub fn popBatch(self: *EventQueue, buffer: []Event, max_count: usize) usize {
        const read_pos = self.read_pos.load(.monotonic);
        const write_pos = self.write_pos.load(.acquire);
        
        const available = write_pos - read_pos;
        const count = @min(available, @min(max_count, buffer.len));
        
        if (count == 0) return 0;
        
        // Copy events
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const index = (read_pos + i) & (QUEUE_SIZE - 1);
            buffer[i] = self.events[index];
        }
        
        // Update read position
        _ = self.read_pos.fetchAdd(count, .release);
        
        return count;
    }

    /// Get pending event count
    pub fn pending(self: *EventQueue) usize {
        const read_pos = self.read_pos.load(.acquire);
        const write_pos = self.write_pos.load(.acquire);
        return write_pos - read_pos;
    }
};