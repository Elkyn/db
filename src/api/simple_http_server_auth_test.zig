const std = @import("std");
const testing = std.testing;
const SimpleHttpServer = @import("simple_http_server.zig").SimpleHttpServer;
const Storage = @import("../storage/storage.zig").Storage;

test "SimpleHttpServer: auth token creation" {
    const allocator = testing.allocator;
    
    // Create storage
    var storage = try Storage.init(allocator, null);
    defer storage.deinit();
    
    // Create server
    var server = try SimpleHttpServer.init(allocator, &storage, 0);
    defer server.deinit();
    
    // Enable auth
    try server.enableAuth("test-secret", false);
    
    // Start server in background
    const server_thread = try std.Thread.spawn(.{}, testServerStart, .{&server});
    defer server_thread.detach();
    
    // Give server time to start
    std.time.sleep(100 * std.time.ns_per_ms);
    
    // Test token creation
    const client = try std.net.tcpConnectToAddress(server.server.listen_address);
    defer client.close();
    
    const request_body = 
        \\{"uid": "test-user", "email": "test@example.com"}
    ;
    
    const request = try std.fmt.allocPrint(allocator, 
        "POST /auth/token HTTP/1.1\r\n" ++
        "Content-Length: {d}\r\n" ++
        "\r\n" ++
        "{s}",
        .{ request_body.len, request_body }
    );
    defer allocator.free(request);
    
    _ = try client.write(request);
    
    var response_buf: [4096]u8 = undefined;
    const bytes_read = try client.read(&response_buf);
    const response = response_buf[0..bytes_read];
    
    // Check response
    try testing.expect(std.mem.indexOf(u8, response, "200 OK") != null);
    try testing.expect(std.mem.indexOf(u8, response, "\"token\"") != null);
    try testing.expect(std.mem.indexOf(u8, response, "\"expires_in\"") != null);
}

test "SimpleHttpServer: auth protection" {
    const allocator = testing.allocator;
    
    // Create storage
    var storage = try Storage.init(allocator, null);
    defer storage.deinit();
    
    // Create server
    var server = try SimpleHttpServer.init(allocator, &storage, 0);
    defer server.deinit();
    
    // Enable auth with required flag
    try server.enableAuth("test-secret", true);
    
    // Start server in background
    const server_thread = try std.Thread.spawn(.{}, testServerStart, .{&server});
    defer server_thread.detach();
    
    // Give server time to start
    std.time.sleep(100 * std.time.ns_per_ms);
    
    // Test unauthorized request
    const client = try std.net.tcpConnectToAddress(server.server.listen_address);
    defer client.close();
    
    const request = "GET /test HTTP/1.1\r\n\r\n";
    _ = try client.write(request);
    
    var response_buf: [4096]u8 = undefined;
    const bytes_read = try client.read(&response_buf);
    const response = response_buf[0..bytes_read];
    
    // Should get 401 Unauthorized
    try testing.expect(std.mem.indexOf(u8, response, "401 Unauthorized") != null);
}

test "SimpleHttpServer: auth with valid token" {
    const allocator = testing.allocator;
    
    // Create storage
    var storage = try Storage.init(allocator, null);
    defer storage.deinit();
    
    // Create server
    var server = try SimpleHttpServer.init(allocator, &storage, 0);
    defer server.deinit();
    
    // Enable auth
    try server.enableAuth("test-secret", true);
    
    // Create a valid token
    var jwt = @import("../auth/jwt.zig").JWT.init(allocator, "test-secret");
    const claims = @import("../auth/jwt.zig").Claims{
        .uid = "test-user",
        .email = "test@example.com",
        .iat = std.time.timestamp(),
        .exp = std.time.timestamp() + 3600,
    };
    const token = try jwt.create(claims);
    defer allocator.free(token);
    
    // Start server in background
    const server_thread = try std.Thread.spawn(.{}, testServerStart, .{&server});
    defer server_thread.detach();
    
    // Give server time to start
    std.time.sleep(100 * std.time.ns_per_ms);
    
    // Test authorized request
    const client = try std.net.tcpConnectToAddress(server.server.listen_address);
    defer client.close();
    
    const request = try std.fmt.allocPrint(allocator,
        "GET /test HTTP/1.1\r\n" ++
        "Authorization: Bearer {s}\r\n" ++
        "\r\n",
        .{token}
    );
    defer allocator.free(request);
    
    _ = try client.write(request);
    
    var response_buf: [4096]u8 = undefined;
    const bytes_read = try client.read(&response_buf);
    const response = response_buf[0..bytes_read];
    
    // Should get 404 Not Found (path doesn't exist, but auth passed)
    try testing.expect(std.mem.indexOf(u8, response, "404 Not Found") != null);
}

fn testServerStart(server: *SimpleHttpServer) void {
    server.start() catch {};
}