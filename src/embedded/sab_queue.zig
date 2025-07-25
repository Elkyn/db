const std = @import("std");

/// SharedArrayBuffer-based operation queue for zero N-API overhead
pub const SABQueue = struct {
    buffer: []u8,           // Points to SharedArrayBuffer memory
    head: *u32,             // Atomic head pointer (consumer)
    tail: *u32,             // Atomic tail pointer (producer)
    buffer_size: u32,
    running: std.atomic.Value(bool),
    
    // Operation types
    pub const OP_SET = 1;
    pub const OP_DELETE = 2;
    pub const OP_SHUTDOWN = 255;
    
    // Fixed-size operation header (48 bytes for alignment)
    pub const OperationHeader = packed struct {
        op_type: u32,       // Operation type
        path_offset: u32,   // Offset to path in data section
        path_length: u32,   // Length of path
        value_offset: u32,  // Offset to value in data section
        value_length: u32,  // Length of value (0 for deletes)
        sequence: u64,      // Sequence number for ordering
        reserved: u64,      // Reserved for future use
        
        comptime {
            std.debug.assert(@sizeOf(OperationHeader) == 48);
        }
    };
    
    pub fn init(sab_ptr: [*]u8, size: u32) SABQueue {
        // Layout: [head:4][tail:4][data:size-8]
        const head_ptr = @as(*u32, @ptrCast(@alignCast(sab_ptr)));
        const tail_ptr = @as(*u32, @ptrCast(@alignCast(sab_ptr + 4)));
        const data_ptr = sab_ptr + 8;
        const data_size = size - 8;
        
        // Initialize head/tail to 0
        @atomicStore(u32, head_ptr, 0, .release);
        @atomicStore(u32, tail_ptr, 0, .release);
        
        return SABQueue{
            .buffer = data_ptr[0..data_size],
            .head = head_ptr,
            .tail = tail_ptr,
            .buffer_size = data_size,
            .running = std.atomic.Value(bool).init(true),
        };
    }
    
    /// Consumer: Read next operation from queue
    pub fn dequeue(self: *SABQueue) ?OperationHeader {
        const head = @atomicLoad(u32, self.head, .acquire);
        const tail = @atomicLoad(u32, self.tail, .acquire);
        
        // Check if queue is empty
        if (head == tail) return null;
        
        // Calculate next head position
        const next_head = (head + @sizeOf(OperationHeader)) % self.buffer_size;
        
        // Ensure we don't read past tail (with wrap-around)
        const available = if (tail >= head) 
            tail - head 
        else 
            self.buffer_size - head + tail;
            
        if (available < @sizeOf(OperationHeader)) return null;
        
        // Read operation header safely (avoid alignment issues)
        const header_bytes = self.buffer[head..head + @sizeOf(OperationHeader)];
        var header: OperationHeader = undefined;
        @memcpy(std.mem.asBytes(&header), header_bytes);
        
        // Update head pointer atomically
        @atomicStore(u32, self.head, next_head, .release);
        
        return header;
    }
    
    /// Get path data for an operation
    pub fn getPath(self: *SABQueue, header: OperationHeader) []const u8 {
        const start = header.path_offset % self.buffer_size;
        const end = (start + header.path_length) % self.buffer_size;
        
        if (end > start) {
            // No wrap-around
            return self.buffer[start..end];
        } else {
            // Handle wrap-around by copying to temporary buffer
            // For now, assume no wrap-around for simplicity
            // TODO: Handle wrap-around case
            return self.buffer[start..start + header.path_length];
        }
    }
    
    /// Get value data for an operation
    pub fn getValue(self: *SABQueue, header: OperationHeader) ?[]const u8 {
        if (header.value_length == 0) return null;
        
        const start = header.value_offset % self.buffer_size;
        const end = (start + header.value_length) % self.buffer_size;
        
        if (end > start) {
            return self.buffer[start..end];
        } else {
            // Handle wrap-around case
            // TODO: Handle wrap-around properly
            return self.buffer[start..start + header.value_length];
        }
    }
    
    /// Check if we should stop processing
    pub fn shouldStop(self: *SABQueue) bool {
        return !self.running.load(.acquire);
    }
    
    /// Signal shutdown
    pub fn shutdown(self: *SABQueue) void {
        self.running.store(false, .release);
    }
    
    /// Get queue statistics
    pub fn stats(self: *SABQueue) struct { head: u32, tail: u32, pending: u32 } {
        const head = @atomicLoad(u32, self.head, .acquire);
        const tail = @atomicLoad(u32, self.tail, .acquire);
        
        const pending = if (tail >= head) 
            tail - head 
        else 
            self.buffer_size - head + tail;
            
        return .{ 
            .head = head, 
            .tail = tail, 
            .pending = pending / @sizeOf(OperationHeader) 
        };
    }
};