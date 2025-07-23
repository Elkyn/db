const std = @import("std");

const MAX_PATH_LENGTH = 1024;
const PATH_SEPARATOR = '/';

pub const PathError = error{
    InvalidPath,
    PathTooLong,
    EmptySegment,
};

/// Represents a parsed tree path with its segments
pub const Path = struct {
    raw: []const u8,
    segments: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, raw_path: []const u8) !Path {
        if (raw_path.len == 0 or raw_path[0] != PATH_SEPARATOR) {
            return error.InvalidPath;
        }
        
        if (raw_path.len > MAX_PATH_LENGTH) {
            return error.PathTooLong;
        }

        // Check for empty segments (consecutive separators)
        var i: usize = 0;
        while (i < raw_path.len - 1) : (i += 1) {
            if (raw_path[i] == PATH_SEPARATOR and raw_path[i + 1] == PATH_SEPARATOR) {
                return error.EmptySegment;
            }
        }

        // Count segments
        var segment_count: usize = 0;
        var iter = std.mem.tokenizeScalar(u8, raw_path[1..], PATH_SEPARATOR);
        while (iter.next()) |_| {
            segment_count += 1;
        }

        // Allocate segments array
        const segments = try allocator.alloc([]const u8, segment_count);
        errdefer allocator.free(segments);

        // Parse segments
        var idx: usize = 0;
        iter = std.mem.tokenizeScalar(u8, raw_path[1..], PATH_SEPARATOR);
        while (iter.next()) |segment| {
            segments[idx] = segment;
            idx += 1;
        }

        return Path{
            .raw = raw_path,
            .segments = segments,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Path) void {
        self.allocator.free(self.segments);
    }

    pub fn parent(self: Path) ?[]const u8 {
        if (self.segments.len == 0) return null;
        
        const last_sep = std.mem.lastIndexOf(u8, self.raw, &[_]u8{PATH_SEPARATOR});
        if (last_sep == null or last_sep.? == 0) return "/";
        
        return self.raw[0..last_sep.?];
    }

    pub fn isRoot(self: Path) bool {
        return self.segments.len == 0;
    }

    pub fn depth(self: Path) usize {
        return self.segments.len;
    }
};

/// Normalize a path by removing trailing slashes and validating format
pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (path.len == 0 or path[0] != PATH_SEPARATOR) {
        return error.InvalidPath;
    }
    
    // Root path is already normalized
    if (std.mem.eql(u8, path, "/")) {
        return try allocator.dupe(u8, path);
    }
    
    // Remove trailing slash
    if (path[path.len - 1] == PATH_SEPARATOR) {
        return try allocator.dupe(u8, path[0..path.len - 1]);
    }
    
    return try allocator.dupe(u8, path);
}

/// Check if a path matches a pattern with wildcards
pub fn pathMatches(path: []const u8, pattern: []const u8) bool {
    var path_iter = std.mem.tokenizeScalar(u8, path[1..], PATH_SEPARATOR);
    var pattern_iter = std.mem.tokenizeScalar(u8, pattern[1..], PATH_SEPARATOR);
    
    while (true) {
        const path_seg = path_iter.next();
        const pattern_seg = pattern_iter.next();
        
        // Both exhausted = match
        if (path_seg == null and pattern_seg == null) return true;
        
        // One exhausted = no match
        if (path_seg == null or pattern_seg == null) return false;
        
        // Check segment match
        if (!std.mem.eql(u8, pattern_seg.?, "*") and !std.mem.eql(u8, path_seg.?, pattern_seg.?)) {
            return false;
        }
    }
}

/// Extract variable values from a path given a pattern
/// Example: path="/users/123/posts/456", pattern="/users/$userId/posts/$postId"
/// Returns: {"userId": "123", "postId": "456"}
pub fn extractVariables(allocator: std.mem.Allocator, path: []const u8, pattern: []const u8) !std.StringHashMap([]const u8) {
    var variables = std.StringHashMap([]const u8).init(allocator);
    errdefer variables.deinit();
    
    var path_iter = std.mem.tokenizeScalar(u8, path[1..], PATH_SEPARATOR);
    var pattern_iter = std.mem.tokenizeScalar(u8, pattern[1..], PATH_SEPARATOR);
    
    while (true) {
        const path_seg = path_iter.next();
        const pattern_seg = pattern_iter.next();
        
        if (path_seg == null and pattern_seg == null) break;
        if (path_seg == null or pattern_seg == null) return error.PatternMismatch;
        
        // Check if pattern segment is a variable
        if (pattern_seg.?[0] == '$') {
            const var_name = pattern_seg.?[1..];
            try variables.put(var_name, path_seg.?);
        } else if (!std.mem.eql(u8, path_seg.?, pattern_seg.?)) {
            return error.PatternMismatch;
        }
    }
    
    return variables;
}