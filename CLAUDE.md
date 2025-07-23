# Elkyn DB Development Guidelines

This document helps Claude (and other developers) maintain consistent, high-quality code in the Elkyn DB project.

## Core Principles

1. **Performance First** - Every microsecond counts for sub-500ms boot
2. **Test Everything** - 100% coverage is the minimum
3. **Zero Allocations** - Use stack allocation and arenas where possible
4. **Fail Fast** - Clear errors at compile time > runtime errors

## Code Style

### Zig Conventions

```zig
// File names: snake_case.zig
// Types: PascalCase
// Functions: camelCase
// Constants: UPPER_SNAKE_CASE
// Variables: snake_case

const std = @import("std");
const lmdb = @import("lmdb");

const MAX_PATH_LENGTH = 1024;

pub const TreeNode = struct {
    path: []const u8,
    value: Value,
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !TreeNode {
        return TreeNode{
            .path = try allocator.dupe(u8, path),
            .value = .{ .null = {} },
        };
    }
};
```

### Error Handling

Always use explicit error types:

```zig
const StorageError = error{
    PathTooLong,
    InvalidPath,
    PermissionDenied,
    NotFound,
};

pub fn get(self: *Storage, path: []const u8) StorageError!Value {
    if (path.len > MAX_PATH_LENGTH) return error.PathTooLong;
    // ...
}
```

### Testing

Every module must have a corresponding test file:

```zig
// storage.zig -> storage_test.zig

test "storage: basic get/set operations" {
    var storage = try Storage.init(testing.allocator);
    defer storage.deinit();
    
    try storage.set("/users/123", .{ .string = "Alice" });
    
    const result = try storage.get("/users/123");
    try testing.expectEqualStrings("Alice", result.string);
}

test "storage: handles missing keys" {
    var storage = try Storage.init(testing.allocator);
    defer storage.deinit();
    
    const result = storage.get("/not/found");
    try testing.expectError(error.NotFound, result);
}
```

### Memory Management

Use arenas for request-scoped allocations:

```zig
pub fn handleRequest(self: *Server, request: Request) !Response {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    
    const allocator = arena.allocator();
    // All allocations in this request will be freed together
}
```

## Project Structure

```
elkyn-db/
├── build.zig              # Build configuration
├── src/
│   ├── main.zig          # Entry point
│   ├── storage/
│   │   ├── lmdb.zig      # LMDB wrapper
│   │   ├── tree.zig      # Tree operations
│   │   └── tree_test.zig
│   ├── auth/
│   │   ├── jwt.zig       # JWT validation
│   │   └── jwt_test.zig
│   ├── rules/
│   │   ├── parser.zig    # Rule parser
│   │   ├── compiler.zig  # Comptime rule compiler
│   │   └── engine.zig    # Runtime evaluation
│   ├── realtime/
│   │   ├── observable.zig # Event system
│   │   ├── websocket.zig  # WS handler
│   │   └── subscription.zig
│   └── api/
│       ├── rest.zig      # HTTP endpoints
│       └── rest_test.zig
├── tests/
│   └── integration/      # End-to-end tests
└── bench/               # Performance benchmarks
```

## Development Workflow

### Before Implementing

1. Write the test first (TDD)
2. Define error cases
3. Consider performance implications
4. Check if similar code exists

### Implementation Checklist

- [ ] All public functions have doc comments
- [ ] Error cases are handled explicitly  
- [ ] No unnecessary allocations
- [ ] Tests pass with `zig build test`
- [ ] Benchmarks show no regression

### Testing Commands

```bash
# Run all tests
zig build test

# Run specific test
zig build test -Dtest-filter="storage"

# Run with coverage
zig build test -Dtest-coverage

# Run benchmarks
zig build bench
```

## Performance Guidelines

### Measure Everything

```zig
const timer = try std.time.Timer.start();
defer {
    const elapsed = timer.read();
    log.debug("Operation took {d}ns", .{elapsed});
}
```

### Allocation Tracking

```zig
test "no allocations in hot path" {
    const allocator = std.testing.allocator;
    
    var storage = try Storage.init(allocator);
    defer storage.deinit();
    
    // This should not allocate
    const before = allocator.total_allocated;
    _ = try storage.get("/users/123");
    const after = allocator.total_allocated;
    
    try testing.expectEqual(before, after);
}
```

## Common Patterns

### Path Handling

```zig
pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    // Always start with /
    if (!std.mem.startsWith(u8, path, "/")) {
        return error.InvalidPath;
    }
    
    // Remove trailing slash except for root
    if (path.len > 1 and std.mem.endsWith(u8, path, "/")) {
        return allocator.dupe(u8, path[0..path.len-1]);
    }
    
    return allocator.dupe(u8, path);
}
```

### Comptime Rule Generation

```zig
fn compileRule(comptime rule: []const u8) type {
    return struct {
        pub fn evaluate(context: RuleContext) bool {
            // Generate specialized code at compile time
            if (comptime std.mem.indexOf(u8, rule, "auth.uid")) {
                if (!context.auth) return false;
                // ... generated code
            }
        }
    };
}
```

## Git Commit Style

```
feat: add real-time subscription system
fix: prevent memory leak in path normalization  
test: add benchmarks for rule evaluation
perf: optimize tree traversal using path indexes
docs: update API examples in README
```

## Questions to Ask Yourself

1. Can this be done at compile time?
2. Does this allocate? Can it be avoided?
3. Is the error message helpful to developers?
4. Would this code be clear to someone new?
5. Is there a test for this edge case?

## Remember

- Zig's comptime is your friend - use it for rule compilation
- The allocator is always explicit - never hide allocations
- Errors are values - handle them explicitly
- Tests are documentation - make them clear
- Performance is a feature - measure it