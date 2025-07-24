const std = @import("std");
const crypto = std.crypto;
const base64 = std.base64;

const log = std.log.scoped(.jwt);

/// JWT header structure
const Header = struct {
    alg: []const u8,
    typ: []const u8,
};

/// Standard JWT claims
pub const Claims = struct {
    // Standard claims
    iss: ?[]const u8 = null, // Issuer
    sub: ?[]const u8 = null, // Subject
    aud: ?[]const u8 = null, // Audience
    exp: ?i64 = null, // Expiration time
    nbf: ?i64 = null, // Not before
    iat: ?i64 = null, // Issued at
    jti: ?[]const u8 = null, // JWT ID
    
    // Custom claims for Elkyn DB
    uid: ?[]const u8 = null, // User ID
    email: ?[]const u8 = null, // Email
    roles: ?[]const []const u8 = null, // User roles
    
    // Allow arbitrary additional claims
    extra: ?std.json.Value = null,
    
    pub fn deinit(self: *Claims, allocator: std.mem.Allocator) void {
        if (self.uid) |uid| allocator.free(uid);
        if (self.email) |email| allocator.free(email);
        if (self.iss) |iss| allocator.free(iss);
        if (self.sub) |sub| allocator.free(sub);
        if (self.aud) |aud| allocator.free(aud);
        if (self.jti) |jti| allocator.free(jti);
        // TODO: handle roles array
    }
};

/// JWT validation result
pub const ValidationResult = struct {
    valid: bool,
    claims: Claims,
    error_message: ?[]const u8 = null,
    
    pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        self.claims.deinit(allocator);
    }
};

/// JWT decoder and validator
pub const JWT = struct {
    allocator: std.mem.Allocator,
    secret: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, secret: []const u8) JWT {
        return JWT{
            .allocator = allocator,
            .secret = secret,
        };
    }
    
    /// Validate and decode a JWT token
    pub fn validate(self: *JWT, token: []const u8) !ValidationResult {
        // Split token into parts
        var parts = std.mem.tokenizeScalar(u8, token, '.');
        
        const header_b64 = parts.next() orelse return error.InvalidToken;
        const payload_b64 = parts.next() orelse return error.InvalidToken;
        const signature_b64 = parts.next() orelse return error.InvalidToken;
        
        // Ensure no extra parts
        if (parts.next() != null) return error.InvalidToken;
        
        // Decode header
        const header_json = try self.decodeBase64Url(header_b64);
        defer self.allocator.free(header_json);
        
        const header_parsed = try std.json.parseFromSlice(Header, self.allocator, header_json, .{});
        defer header_parsed.deinit();
        
        // Only support HS256 for now
        if (!std.mem.eql(u8, header_parsed.value.alg, "HS256")) {
            return ValidationResult{
                .valid = false,
                .claims = .{},
                .error_message = "Unsupported algorithm",
            };
        }
        
        // Verify signature
        const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{header_b64, payload_b64});
        defer self.allocator.free(message);
        
        const expected_signature = try self.computeHS256(message);
        defer self.allocator.free(expected_signature);
        
        const provided_signature = try self.decodeBase64Url(signature_b64);
        defer self.allocator.free(provided_signature);
        
        if (!std.mem.eql(u8, expected_signature, provided_signature)) {
            return ValidationResult{
                .valid = false,
                .claims = .{},
                .error_message = "Invalid signature",
            };
        }
        
        // Decode and parse claims
        const payload_json = try self.decodeBase64Url(payload_b64);
        defer self.allocator.free(payload_json);
        
        const claims_parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, payload_json, .{});
        defer claims_parsed.deinit();
        
        // Extract standard claims
        var claims = Claims{};
        if (claims_parsed.value.object.get("uid")) |uid| {
            if (uid == .string) claims.uid = try self.allocator.dupe(u8, uid.string);
        }
        if (claims_parsed.value.object.get("email")) |email| {
            if (email == .string) claims.email = try self.allocator.dupe(u8, email.string);
        }
        if (claims_parsed.value.object.get("exp")) |exp| {
            if (exp == .integer) claims.exp = exp.integer;
        }
        if (claims_parsed.value.object.get("iat")) |iat| {
            if (iat == .integer) claims.iat = iat.integer;
        }
        
        // Check expiration
        if (claims.exp) |exp_time| {
            const now = std.time.timestamp();
            if (now > exp_time) {
                return ValidationResult{
                    .valid = false,
                    .claims = claims,
                    .error_message = "Token expired",
                };
            }
        }
        
        return ValidationResult{
            .valid = true,
            .claims = claims,
        };
    }
    
    /// Create a signed JWT token (for testing)
    pub fn create(self: *JWT, claims: Claims) ![]const u8 {
        // Create header
        const header = Header{
            .alg = "HS256",
            .typ = "JWT",
        };
        
        const header_json = try std.json.stringifyAlloc(self.allocator, header, .{});
        defer self.allocator.free(header_json);
        
        // Create payload
        var payload_obj = std.json.ObjectMap.init(self.allocator);
        defer payload_obj.deinit();
        
        if (claims.uid) |uid| {
            try payload_obj.put("uid", .{ .string = uid });
        }
        if (claims.email) |email| {
            try payload_obj.put("email", .{ .string = email });
        }
        if (claims.exp) |exp| {
            try payload_obj.put("exp", .{ .integer = exp });
        }
        if (claims.iat) |iat| {
            try payload_obj.put("iat", .{ .integer = iat });
        }
        
        const payload_value = std.json.Value{ .object = payload_obj };
        const payload_json = try std.json.stringifyAlloc(self.allocator, payload_value, .{});
        defer self.allocator.free(payload_json);
        
        // Base64 encode
        const header_b64 = try self.encodeBase64Url(header_json);
        defer self.allocator.free(header_b64);
        
        const payload_b64 = try self.encodeBase64Url(payload_json);
        defer self.allocator.free(payload_b64);
        
        // Create signature
        const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{header_b64, payload_b64});
        defer self.allocator.free(message);
        
        const signature = try self.computeHS256(message);
        defer self.allocator.free(signature);
        
        const signature_b64 = try self.encodeBase64Url(signature);
        defer self.allocator.free(signature_b64);
        
        // Combine parts
        return std.fmt.allocPrint(self.allocator, "{s}.{s}.{s}", .{
            header_b64,
            payload_b64,
            signature_b64,
        });
    }
    
    fn computeHS256(self: *JWT, message: []const u8) ![]const u8 {
        var hmac = crypto.auth.hmac.sha2.HmacSha256.init(self.secret);
        hmac.update(message);
        var result: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
        hmac.final(&result);
        
        const output = try self.allocator.alloc(u8, result.len);
        @memcpy(output, &result);
        return output;
    }
    
    fn encodeBase64Url(self: *JWT, data: []const u8) ![]const u8 {
        const encoder = base64.url_safe_no_pad.Encoder;
        const len = encoder.calcSize(data.len);
        const output = try self.allocator.alloc(u8, len);
        _ = encoder.encode(output, data);
        return output;
    }
    
    fn decodeBase64Url(self: *JWT, data: []const u8) ![]const u8 {
        const decoder = base64.url_safe_no_pad.Decoder;
        const len = decoder.calcSizeForSlice(data) catch return error.InvalidToken;
        const output = try self.allocator.alloc(u8, len);
        decoder.decode(output, data) catch {
            self.allocator.free(output);
            return error.InvalidToken;
        };
        return output;
    }
};