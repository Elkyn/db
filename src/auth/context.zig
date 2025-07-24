const std = @import("std");

/// Authentication context for a request
pub const AuthContext = struct {
    /// Is the user authenticated?
    authenticated: bool = false,
    
    /// User ID from the token
    uid: ?[]const u8 = null,
    
    /// User email
    email: ?[]const u8 = null,
    
    /// User roles
    roles: []const []const u8 = &.{},
    
    /// Token expiration timestamp
    exp: ?i64 = null,
    
    /// Original token (for forwarding)
    token: ?[]const u8 = null,
    
    pub fn isAuthenticated(self: AuthContext) bool {
        return self.authenticated and self.uid != null;
    }
    
    pub fn hasRole(self: AuthContext, role: []const u8) bool {
        for (self.roles) |r| {
            if (std.mem.eql(u8, r, role)) return true;
        }
        return false;
    }
    
    pub fn isAdmin(self: AuthContext) bool {
        return self.hasRole("admin");
    }
    
    pub fn deinit(self: *AuthContext, allocator: std.mem.Allocator) void {
        if (self.uid) |uid| allocator.free(uid);
        if (self.email) |email| allocator.free(email);
        if (self.token) |token| allocator.free(token);
        
        // Free each role string and the array itself
        for (self.roles) |role| {
            allocator.free(role);
        }
        if (self.roles.len > 0) {
            allocator.free(self.roles);
        }
    }
};