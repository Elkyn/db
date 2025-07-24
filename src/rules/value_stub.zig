// Stub Value type for rules testing
pub const Value = struct {
    data: []const u8,
    
    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};