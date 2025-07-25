const std = @import("std");
const constants = @import("constants.zig");

/// Configuration for Elkyn DB server
pub const Config = struct {
    // Server settings
    port: u16 = constants.DEFAULT_SERVER_PORT,
    host: []const u8 = constants.SERVER_ADDRESS,
    data_dir: []const u8 = constants.DEFAULT_DATA_DIR,
    
    // Authentication settings
    jwt_secret: ?[]const u8 = null,
    require_auth: bool = false,
    allow_token_generation: bool = false,
    
    // Performance settings
    thread_count: ?usize = null,
    lmdb_map_size: usize = constants.LMDB_MAP_SIZE,
    
    // Logging settings
    log_level: LogLevel = .info,
    log_format: LogFormat = .text,
    
    pub const LogLevel = enum {
        debug,
        info,
        warn,
        @"error",
    };
    
    pub const LogFormat = enum {
        text,
        json,
    };
    
    /// Load configuration from environment variables
    pub fn fromEnv(allocator: std.mem.Allocator) !Config {
        var config = Config{};
        
        // Port
        if (std.process.getEnvVarOwned(allocator, "ELKYN_PORT")) |port_str| {
            defer allocator.free(port_str);
            config.port = std.fmt.parseInt(u16, port_str, 10) catch constants.DEFAULT_SERVER_PORT;
        } else |_| {}
        
        // Host
        if (std.process.getEnvVarOwned(allocator, "ELKYN_HOST")) |host_str| {
            config.host = host_str; // Note: caller must manage this memory
        } else |_| {}
        
        // Data directory
        if (std.process.getEnvVarOwned(allocator, "ELKYN_DATA_DIR")) |data_dir_str| {
            config.data_dir = data_dir_str; // Note: caller must manage this memory
        } else |_| {}
        
        // JWT Secret
        if (std.process.getEnvVarOwned(allocator, "ELKYN_JWT_SECRET")) |jwt_secret_str| {
            config.jwt_secret = jwt_secret_str; // Note: caller must manage this memory
        } else |_| {}
        
        // Require auth
        if (std.process.getEnvVarOwned(allocator, "ELKYN_REQUIRE_AUTH")) |auth_str| {
            defer allocator.free(auth_str);
            config.require_auth = std.mem.eql(u8, auth_str, "true") or std.mem.eql(u8, auth_str, "1");
        } else |_| {}
        
        // Thread count
        if (std.process.getEnvVarOwned(allocator, "ELKYN_THREADS")) |thread_str| {
            defer allocator.free(thread_str);
            config.thread_count = std.fmt.parseInt(usize, thread_str, 10) catch null;
        } else |_| {}
        
        // Log level
        if (std.process.getEnvVarOwned(allocator, "ELKYN_LOG_LEVEL")) |log_str| {
            defer allocator.free(log_str);
            if (std.mem.eql(u8, log_str, "debug")) config.log_level = .debug
            else if (std.mem.eql(u8, log_str, "info")) config.log_level = .info
            else if (std.mem.eql(u8, log_str, "warn")) config.log_level = .warn
            else if (std.mem.eql(u8, log_str, "error")) config.log_level = .@"error";
        } else |_| {}
        
        return config;
    }
    
    /// Print configuration (without secrets)
    pub fn print(self: Config) void {
        std.debug.print("=== Elkyn DB Configuration ===\n");
        std.debug.print("Server: {}:{}\n", .{ self.host, self.port });
        std.debug.print("Data directory: {s}\n", .{self.data_dir});
        std.debug.print("Authentication: {s}\n", .{if (self.jwt_secret != null) "enabled" else "disabled"});
        if (self.jwt_secret != null) {
            std.debug.print("Require auth: {}\n", .{self.require_auth});
        }
        std.debug.print("Thread count: {}\n", .{self.thread_count orelse 4});
        std.debug.print("Log level: {s}\n", .{@tagName(self.log_level)});
        std.debug.print("===============================\n");
    }
};