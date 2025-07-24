// Centralized logging utilities for consistent error messages

const std = @import("std");
const constants = @import("constants.zig");

// Define log levels
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
    fatal,
};

// Error context struct for detailed error messages
pub const ErrorContext = struct {
    operation: []const u8,
    path: ?[]const u8 = null,
    user: ?[]const u8 = null,
    details: ?[]const u8 = null,
};

// Format error messages with context
pub fn formatError(allocator: std.mem.Allocator, context: ErrorContext, err: anyerror) ![]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();
    
    try parts.append("Operation failed: ");
    try parts.append(context.operation);
    
    if (context.path) |path| {
        try parts.append(" [path: ");
        try parts.append(path);
        try parts.append("]");
    }
    
    if (context.user) |user| {
        try parts.append(" [user: ");
        try parts.append(user);
        try parts.append("]");
    }
    
    try parts.append(" - Error: ");
    try parts.append(@errorName(err));
    
    if (context.details) |details| {
        try parts.append(" - ");
        try parts.append(details);
    }
    
    return std.mem.join(allocator, "", parts.items);
}

// Logging helpers for consistent patterns
pub fn logDatabaseError(comptime scope: @Type(.EnumLiteral), context: ErrorContext, err: anyerror) void {
    const log = std.log.scoped(scope);
    
    switch (err) {
        error.NotFound => log.err("{s}: Path not found{s}", .{
            context.operation,
            if (context.path) |p| std.fmt.allocPrint(std.heap.page_allocator, " - {s}", .{p}) catch " - <path>" else "",
        }),
        error.PermissionDenied => log.err("{s}: Permission denied{s}{s}", .{
            context.operation,
            if (context.path) |p| std.fmt.allocPrint(std.heap.page_allocator, " for path: {s}", .{p}) catch "" else "",
            if (context.user) |u| std.fmt.allocPrint(std.heap.page_allocator, " (user: {s})", .{u}) catch "" else "",
        }),
        error.DiskFull => log.err("{s}: Database disk full - cannot complete operation", .{context.operation}),
        error.Corrupted => log.err("{s}: Database corruption detected - immediate attention required", .{context.operation}),
        else => log.err("{s}: {s}{s}", .{
            context.operation,
            @errorName(err),
            if (context.details) |d| std.fmt.allocPrint(std.heap.page_allocator, " - {s}", .{d}) catch "" else "",
        }),
    }
}

pub fn logAuthError(comptime scope: @Type(.EnumLiteral), context: ErrorContext, err: anyerror) void {
    const log = std.log.scoped(scope);
    
    switch (err) {
        error.InvalidToken => log.warn("Authentication failed: Invalid token{s}", .{
            if (context.details) |d| std.fmt.allocPrint(std.heap.page_allocator, " - {s}", .{d}) catch "" else "",
        }),
        error.TokenExpired => log.info("Authentication failed: Token expired{s}", .{
            if (context.user) |u| std.fmt.allocPrint(std.heap.page_allocator, " for user: {s}", .{u}) catch "" else "",
        }),
        error.Unauthorized => log.warn("Access denied: {s}{s}", .{
            context.operation,
            if (context.path) |p| std.fmt.allocPrint(std.heap.page_allocator, " to path: {s}", .{p}) catch "" else "",
        }),
        else => log.err("Authentication error in {s}: {s}", .{context.operation, @errorName(err)}),
    }
}

pub fn logServerError(comptime scope: @Type(.EnumLiteral), context: ErrorContext, err: anyerror) void {
    const log = std.log.scoped(scope);
    
    switch (err) {
        error.AddressInUse => log.err("Cannot start server: Port already in use", .{}),
        error.NetworkUnreachable => log.err("Cannot start server: Network unreachable", .{}),
        error.ConnectionResetByPeer => log.debug("Client disconnected during {s}", .{context.operation}),
        error.BrokenPipe => log.debug("Client closed connection during {s}", .{context.operation}),
        else => log.err("Server error in {s}: {s}", .{context.operation, @errorName(err)}),
    }
}

// Performance logging helpers
pub fn logBootTime(comptime scope: @Type(.EnumLiteral), component: []const u8, time_ns: u64) void {
    const log = std.log.scoped(scope);
    const time_ms = @as(f64, @floatFromInt(time_ns)) / 1_000_000.0;
    
    if (time_ms > 100.0) {
        log.warn("{s} initialization slow: {d:.3}ms", .{component, time_ms});
    } else {
        log.debug("{s} initialized in {d:.3}ms", .{component, time_ms});
    }
}

pub fn logOperationTime(comptime scope: @Type(.EnumLiteral), operation: []const u8, time_ns: u64) void {
    const log = std.log.scoped(scope);
    const time_ms = @as(f64, @floatFromInt(time_ns)) / 1_000_000.0;
    
    if (time_ms > 1000.0) {
        log.warn("Slow operation '{s}': {d:.3}ms", .{operation, time_ms});
    } else if (time_ms > 100.0) {
        log.info("Operation '{s}' took {d:.3}ms", .{operation, time_ms});
    } else {
        log.debug("Operation '{s}' completed in {d:.3}ms", .{operation, time_ms});
    }
}