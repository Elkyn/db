const std = @import("std");
const Value = @import("../storage/value.zig").Value;
const constants = @import("../constants.zig");

const log = std.log.scoped(.sse_manager);

pub const SSEConnection = struct {
    stream: std.net.Stream,
    path: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn sendEvent(self: *SSEConnection, event_type: []const u8, data: []const u8) !void {
        var buffer: [constants.SSE_EVENT_BUFFER_SIZE]u8 = undefined;
        const message = try std.fmt.bufPrint(&buffer, "event: {s}\ndata: {s}\n\n", .{event_type, data});
        _ = self.stream.write(message) catch |err| {
            log.debug("Failed to send event to client: {}", .{err});
            return err;
        };
    }
    
    pub fn sendData(self: *SSEConnection, data: []const u8) !void {
        var buffer: [constants.SSE_EVENT_BUFFER_SIZE]u8 = undefined;
        const message = try std.fmt.bufPrint(&buffer, "data: {s}\n\n", .{data});
        _ = self.stream.write(message) catch |err| {
            log.debug("Failed to send data to client: {}", .{err});
            return err;
        };
    }
    
    pub fn sendHeartbeat(self: *SSEConnection) !void {
        _ = self.stream.write(":heartbeat\n\n") catch |err| {
            log.debug("Failed to send heartbeat: {}", .{err});
            return err;
        };
    }
};

pub const SSEManager = struct {
    allocator: std.mem.Allocator,
    connections: std.ArrayList(SSEConnection),
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator) SSEManager {
        return SSEManager{
            .allocator = allocator,
            .connections = std.ArrayList(SSEConnection).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }
    
    pub fn deinit(self: *SSEManager) void {
        self.connections.deinit();
    }
    
    pub fn addConnection(self: *SSEManager, stream: std.net.Stream, path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const duped_path = try self.allocator.dupe(u8, path);
        try self.connections.append(SSEConnection{
            .stream = stream,
            .path = duped_path,
            .allocator = self.allocator,
        });
        
        log.info("Added SSE connection for path: {s}", .{path});
    }
    
    pub fn removeConnection(self: *SSEManager, stream: std.net.Stream) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var i: usize = 0;
        while (i < self.connections.items.len) {
            if (self.connections.items[i].stream.handle == stream.handle) {
                const conn = self.connections.swapRemove(i);
                self.allocator.free(conn.path);
                log.info("Removed SSE connection for path: {s}", .{conn.path});
                return;
            }
            i += 1;
        }
    }
    
    pub fn notifyValueChanged(self: *SSEManager, path: []const u8, value: ?Value) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        log.info("Notifying {d} connections about change to {s}", .{self.connections.items.len, path});
        
        var i: usize = 0;
        while (i < self.connections.items.len) {
            const conn = &self.connections.items[i];
            
            // Check if this connection is watching this path or a parent path
            if (std.mem.startsWith(u8, path, conn.path) or std.mem.startsWith(u8, conn.path, path)) {
                log.debug("Sending update to connection watching {s}", .{conn.path});
                const json = if (value) |v| try v.toJson(self.allocator) else try self.allocator.dupe(u8, "null");
                defer self.allocator.free(json);
                
                conn.sendData(json) catch |err| {
                    log.debug("Failed to send update to connection: {}", .{err});
                    // Remove dead connection
                    const dead_conn = self.connections.swapRemove(i);
                    self.allocator.free(dead_conn.path);
                    continue;
                };
            }
            
            i += 1;
        }
    }
    
    pub fn sendHeartbeats(self: *SSEManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var i: usize = 0;
        while (i < self.connections.items.len) {
            self.connections.items[i].sendHeartbeat() catch |err| {
                log.debug("Failed to send heartbeat: {}", .{err});
                // Remove dead connection
                const dead_conn = self.connections.swapRemove(i);
                self.allocator.free(dead_conn.path);
                continue;
            };
            i += 1;
        }
    }
};