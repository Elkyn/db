const std = @import("std");
const Storage = @import("../storage/storage.zig").Storage;
const Value = @import("../storage/value.zig").Value;
const SSEManager = @import("../realtime/sse_manager.zig").SSEManager;
const JWT = @import("../auth/jwt.zig").JWT;
const AuthContext = @import("../auth/context.zig").AuthContext;

const log = std.log.scoped(.simple_http);

pub const SimpleHttpServer = struct {
    allocator: std.mem.Allocator,
    server: std.net.Server,
    port: u16,
    storage: *Storage,
    event_emitter: ?*@import("../storage/event_emitter.zig").EventEmitter,
    sse_manager: SSEManager,
    jwt: ?JWT = null,
    require_auth: bool = false,

    pub fn init(allocator: std.mem.Allocator, storage: *Storage, port: u16) !SimpleHttpServer {
        const address = try std.net.Address.parseIp("127.0.0.1", port);
        var server = try address.listen(.{
            .reuse_address = true,
        });
        
        const actual_port = server.listen_address.getPort();
        log.info("Server listening on port {d}", .{actual_port});
        
        return SimpleHttpServer{
            .allocator = allocator,
            .server = server,
            .port = actual_port,
            .storage = storage,
            .event_emitter = null,
            .sse_manager = SSEManager.init(allocator),
        };
    }

    pub fn deinit(self: *SimpleHttpServer) void {
        self.sse_manager.deinit();
        self.server.deinit();
    }
    
    pub fn setEventEmitter(self: *SimpleHttpServer, emitter: *@import("../storage/event_emitter.zig").EventEmitter) void {
        self.event_emitter = emitter;
    }
    
    pub fn enableAuth(self: *SimpleHttpServer, secret: []const u8, require: bool) !void {
        self.jwt = JWT.init(self.allocator, secret);
        self.require_auth = require;
        log.info("Authentication enabled (required: {})", .{require});
    }

    pub fn start(self: *SimpleHttpServer) !void {
        log.info("Server started on port {d}", .{self.port});
        
        // Start heartbeat thread
        const heartbeat_thread = try std.Thread.spawn(.{}, heartbeatLoop, .{self});
        heartbeat_thread.detach();
        
        while (true) {
            const connection = try self.server.accept();
            
            // Handle connection inline (no threading)
            self.handleConnection(connection) catch |err| {
                log.err("Error handling connection: {}", .{err});
            };
        }
    }
    
    fn heartbeatLoop(self: *SimpleHttpServer) void {
        while (true) {
            std.time.sleep(30 * std.time.ns_per_s);
            self.sse_manager.sendHeartbeats();
        }
    }
    
    fn isStaticFileRequest(path: []const u8) bool {
        // Only serve static files for these specific patterns
        if (std.mem.eql(u8, path, "/index.html")) return true;
        if (std.mem.endsWith(u8, path, ".html")) return true;
        if (std.mem.endsWith(u8, path, ".css")) return true;
        if (std.mem.endsWith(u8, path, ".js")) return true;
        if (std.mem.endsWith(u8, path, ".ico")) return true;
        return false;
    }
    
    fn handleSSEThread(self: *SimpleHttpServer, connection: std.net.Server.Connection, watch_path: []const u8) void {
        defer self.allocator.free(watch_path);
        defer connection.stream.close();
        
        self.handleSSE(connection, watch_path) catch |err| {
            log.err("SSE handler error: {}", .{err});
        };
    }

    fn extractAuthContext(self: *SimpleHttpServer, request: []const u8) !AuthContext {
        if (self.jwt == null) {
            return .{ .authenticated = false };
        }
        
        // Look for Authorization header
        var lines = std.mem.tokenizeScalar(u8, request, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, "\r");
            if (std.mem.startsWith(u8, trimmed, "Authorization: Bearer ")) {
                const token = trimmed["Authorization: Bearer ".len..];
                
                // Validate token
                if (self.jwt) |*jwt| {
                    var result = jwt.validate(token) catch {
                        return .{ .authenticated = false };
                    };
                    defer result.deinit(self.allocator);
                    
                    if (result.valid) {
                        return AuthContext{
                            .authenticated = true,
                            .uid = if (result.claims.uid) |uid| try self.allocator.dupe(u8, uid) else null,
                            .email = if (result.claims.email) |email| try self.allocator.dupe(u8, email) else null,
                            .exp = result.claims.exp,
                            .token = try self.allocator.dupe(u8, token),
                        };
                    }
                }
            }
        }
        
        return .{ .authenticated = false };
    }
    
    fn handleConnection(self: *SimpleHttpServer, connection: std.net.Server.Connection) !void {
        var should_close = true;
        defer if (should_close) connection.stream.close();
        
        // Read request
        var buffer: [4096]u8 = undefined;
        const bytes_read = try connection.stream.read(&buffer);
        
        if (bytes_read == 0) return;
        
        // Parse request line
        const request = buffer[0..bytes_read];
        log.debug("Request ({} bytes): {s}", .{bytes_read, request});
        var lines = std.mem.tokenizeScalar(u8, request, '\n');
        const request_line = lines.next() orelse return;
        
        var parts = std.mem.tokenizeScalar(u8, request_line, ' ');
        const method = parts.next() orelse return;
        const path = parts.next() orelse return;
        
        // Extract auth context
        var auth = self.extractAuthContext(request) catch |err| {
            log.err("Failed to extract auth context: {}", .{err});
            return;
        };
        defer auth.deinit(self.allocator);
        
        // Check if this is a browser request to root
        const is_browser = std.mem.indexOf(u8, request, "Accept: text/html") != null;
        if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/") and is_browser) {
            // Redirect browser to dashboard
            const redirect = 
                "HTTP/1.1 302 Found\r\n" ++
                "Location: /index.html\r\n" ++
                "Content-Length: 0\r\n" ++
                "Connection: close\r\n" ++
                "\r\n";
            _ = try connection.stream.write(redirect);
            return;
        }
        
        // Special auth endpoints (always allowed)
        if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/auth/token")) {
            try self.handleCreateToken(connection, request);
            return;
        }
        
        // Check authentication for protected endpoints
        if (self.require_auth and !isStaticFileRequest(path) and !std.mem.eql(u8, path, "/")) {
            if (!auth.isAuthenticated()) {
                try self.sendResponse(connection, 401, "Unauthorized", "Authentication required");
                return;
            }
        }
        
        // Route request
        if (std.mem.eql(u8, method, "GET")) {
            // Check if this is an SSE request
            if (std.mem.endsWith(u8, path, "/.watch")) {
                // For SSE, we need to handle it in a separate thread since it's long-lived
                const watch_path = try self.allocator.dupe(u8, path[0..path.len - 7]); // Remove "/.watch"
                const sse_thread = try std.Thread.spawn(.{}, handleSSEThread, .{self, connection, watch_path});
                sse_thread.detach();
                // Don't close the connection here - it will be managed by the SSE thread
                should_close = false;
                return;
            } else if (isStaticFileRequest(path)) {
                // Serve static files only for specific paths
                try self.handleStaticFile(connection, path);
            } else {
                // All other GET requests are API calls
                try self.handleGet(connection, path, auth);
            }
        } else if (std.mem.eql(u8, method, "PUT")) {
            try self.handlePut(connection, path, request, auth);
        } else if (std.mem.eql(u8, method, "DELETE")) {
            try self.handleDelete(connection, path, auth);
        } else {
            try self.sendResponse(connection, 405, "Method Not Allowed", "");
        }
    }
    
    fn handleGet(self: *SimpleHttpServer, connection: std.net.Server.Connection, path: []const u8, auth: AuthContext) !void {
        _ = auth; // TODO: Use for access control
        var value = self.storage.get(path) catch |err| {
            if (err == error.NotFound) {
                try self.sendResponse(connection, 404, "Not Found", "");
                return;
            }
            log.err("Error getting path {s}: {}", .{path, err});
            try self.sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        defer value.deinit(self.allocator);
        
        const json = value.toJson(self.allocator) catch |err| {
            log.err("Error converting to JSON for path {s}: {}", .{path, err});
            try self.sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        defer self.allocator.free(json);
        
        try self.sendJsonResponse(connection, 200, "OK", json);
    }
    
    fn handlePut(self: *SimpleHttpServer, connection: std.net.Server.Connection, path: []const u8, request: []const u8, auth: AuthContext) !void {
        _ = auth; // TODO: Use for access control
        // Find body
        const body_start = std.mem.indexOf(u8, request, "\r\n\r\n") orelse std.mem.indexOf(u8, request, "\n\n") orelse {
            try self.sendResponse(connection, 400, "Bad Request", "");
            return;
        };
        
        const body = if (std.mem.indexOf(u8, request, "\r\n\r\n")) |idx|
            request[idx + 4 ..]
        else
            request[body_start + 2 ..];
        
        log.debug("Body content: '{s}'", .{body});
        
        // Parse JSON
        var value = Value.fromJson(self.allocator, body) catch |err| {
            log.err("JSON parse error: {}, body: '{s}'", .{err, body});
            try self.sendResponse(connection, 400, "Bad Request", "Invalid JSON");
            return;
        };
        defer value.deinit(self.allocator);
        
        // Store value
        self.storage.set(path, value) catch {
            try self.sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        
        try self.sendResponse(connection, 200, "OK", "");
    }
    
    fn handleDelete(self: *SimpleHttpServer, connection: std.net.Server.Connection, path: []const u8, auth: AuthContext) !void {
        _ = auth; // TODO: Use for access control
        self.storage.delete(path) catch |err| {
            if (err == error.NotFound) {
                try self.sendResponse(connection, 404, "Not Found", "");
                return;
            }
            try self.sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        
        try self.sendResponse(connection, 200, "OK", "");
    }
    
    fn sendResponse(self: *SimpleHttpServer, connection: std.net.Server.Connection, status: u16, status_text: []const u8, body: []const u8) !void {
        _ = self;
        var header_buf: [512]u8 = undefined;
        const headers = try std.fmt.bufPrint(
            &header_buf,
            "HTTP/1.1 {d} {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ status, status_text, body.len }
        );
        
        _ = try connection.stream.write(headers);
        if (body.len > 0) {
            _ = try connection.stream.write(body);
        }
    }
    
    fn sendJsonResponse(self: *SimpleHttpServer, connection: std.net.Server.Connection, status: u16, status_text: []const u8, json: []const u8) !void {
        _ = self;
        var header_buf: [512]u8 = undefined;
        const headers = try std.fmt.bufPrint(
            &header_buf,
            "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ status, status_text, json.len }
        );
        
        _ = try connection.stream.write(headers);
        _ = try connection.stream.write(json);
    }
    
    fn handleStaticFile(self: *SimpleHttpServer, connection: std.net.Server.Connection, request_path: []const u8) !void {
        const path = request_path;
        
        // Build file path relative to web directory
        const file_path = try std.fmt.allocPrint(self.allocator, "web{s}", .{path});
        defer self.allocator.free(file_path);
        
        // Try to open and read the file
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                try self.sendResponse(connection, 404, "Not Found", "File not found");
                return;
            }
            try self.sendResponse(connection, 500, "Internal Server Error", "");
            return;
        };
        defer file.close();
        
        // Get file size
        const file_stat = try file.stat();
        const file_size = file_stat.size;
        
        // Read file content
        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);
        _ = try file.read(content);
        
        // Determine content type
        const content_type = if (std.mem.endsWith(u8, path, ".html"))
            "text/html"
        else if (std.mem.endsWith(u8, path, ".css"))
            "text/css"
        else if (std.mem.endsWith(u8, path, ".js"))
            "application/javascript"
        else
            "text/plain";
        
        // Send response with appropriate content type
        var header_buf: [512]u8 = undefined;
        const headers = try std.fmt.bufPrint(
            &header_buf,
            "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ content_type, content.len }
        );
        
        _ = try connection.stream.write(headers);
        _ = try connection.stream.write(content);
    }
    
    fn handleSSE(self: *SimpleHttpServer, connection: std.net.Server.Connection, watch_path: []const u8) !void {
        // Note: connection.stream.close() is handled by the caller (handleConnection)
        
        // Send SSE headers
        const headers = 
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/event-stream\r\n" ++
            "Cache-Control: no-cache\r\n" ++
            "Connection: keep-alive\r\n" ++
            "\r\n";
        _ = try connection.stream.write(headers);
        
        // Send initial value
        if (self.storage.get(watch_path)) |v| {
            var value = v;
            defer value.deinit(self.allocator);
            const json = try value.toJson(self.allocator);
            defer self.allocator.free(json);
            _ = try connection.stream.write("data: ");
            _ = try connection.stream.write(json);
            _ = try connection.stream.write("\n\n");
        } else |err| {
            if (err == error.NotFound) {
                _ = try connection.stream.write("data: null\n\n");
            } else {
                return;
            }
        }
        
        // Add this connection to SSE manager
        try self.sse_manager.addConnection(connection.stream, watch_path);
        defer self.sse_manager.removeConnection(connection.stream);
        
        // Keep connection alive (heartbeats will be sent by the heartbeat thread)
        while (true) {
            std.time.sleep(1 * std.time.ns_per_s);
            // Check if connection is still alive by trying to write empty string
            _ = connection.stream.write("") catch break;
        }
    }
    
    fn handleCreateToken(self: *SimpleHttpServer, connection: std.net.Server.Connection, request: []const u8) !void {
        // Only allow if auth is enabled
        if (self.jwt == null) {
            try self.sendResponse(connection, 404, "Not Found", "");
            return;
        }
        
        // Find body
        const body_start = std.mem.indexOf(u8, request, "\r\n\r\n") orelse std.mem.indexOf(u8, request, "\n\n") orelse {
            try self.sendResponse(connection, 400, "Bad Request", "");
            return;
        };
        
        const body = if (std.mem.indexOf(u8, request, "\r\n\r\n")) |idx|
            request[idx + 4 ..]
        else
            request[body_start + 2 ..];
        
        // Parse request body
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch {
            try self.sendResponse(connection, 400, "Bad Request", "Invalid JSON");
            return;
        };
        defer parsed.deinit();
        
        // Extract uid and email
        const uid = if (parsed.value.object.get("uid")) |v| 
            (if (v == .string) v.string else null)
        else null;
        
        const email = if (parsed.value.object.get("email")) |v|
            (if (v == .string) v.string else null)
        else null;
        
        if (uid == null) {
            try self.sendResponse(connection, 400, "Bad Request", "uid is required");
            return;
        }
        
        // Create claims
        const claims = @import("../auth/jwt.zig").Claims{
            .uid = uid,
            .email = email,
            .iat = std.time.timestamp(),
            .exp = std.time.timestamp() + 3600, // 1 hour
        };
        
        // Generate token
        if (self.jwt) |*jwt| {
            const token = jwt.create(claims) catch {
                try self.sendResponse(connection, 500, "Internal Server Error", "");
                return;
            };
            defer self.allocator.free(token);
            
            // Create response
            var response_obj = std.json.ObjectMap.init(self.allocator);
            defer response_obj.deinit();
            try response_obj.put("token", .{ .string = token });
            try response_obj.put("expires_in", .{ .integer = 3600 });
            
            const response_value = std.json.Value{ .object = response_obj };
            const response_json = try std.json.stringifyAlloc(self.allocator, response_value, .{});
            defer self.allocator.free(response_json);
            
            try self.sendJsonResponse(connection, 200, "OK", response_json);
        }
    }
};