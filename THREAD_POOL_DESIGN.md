# Thread Pool Design for Elkyn DB

## Overview

This document describes the thread pool implementation for Elkyn DB's HTTP server, designed to handle concurrent requests efficiently while ensuring proper LMDB transaction management.

## Architecture

### Core Components

1. **WorkQueue** (`src/api/thread_pool.zig`)
   - Thread-safe queue for distributing work to pool threads
   - Uses mutex and condition variables for synchronization
   - Supports graceful shutdown

2. **ThreadPool** (`src/api/thread_pool.zig`)
   - Manages a fixed number of worker threads
   - Distributes incoming requests across threads
   - Ensures proper cleanup on shutdown

3. **ThreadPoolHttpServer** (`src/api/thread_pool_server.zig`)
   - Extended version of SimpleHttpServer with thread pool support
   - Maintains compatibility with existing API
   - Handles concurrent requests efficiently

### LMDB Transaction Handling

LMDB has specific requirements for multi-threaded access:

1. **Environment is Thread-Safe**: A single LMDB environment can be shared across threads
2. **Transactions are Thread-Local**: Each thread must use its own transactions
3. **Read Transactions**: Multiple threads can have concurrent read transactions
4. **Write Transactions**: Only one write transaction at a time (LMDB handles serialization)

### Implementation Details

```zig
// Thread pool initialization
var server = try ThreadPoolHttpServer.init(allocator, &storage, port, 8);

// Each request is handled in its own thread
// LMDB transactions are created per-request within the thread
fn handleGet(self: *ThreadPoolHttpServer, ...) !void {
    // Each thread creates its own read transaction
    var value = self.storage.get(path) catch |err| {
        // Transaction is automatically cleaned up
    };
    defer value.deinit(self.allocator);
}
```

### Request Flow

1. Main thread accepts incoming connections
2. Connection wrapped in RequestContext and submitted to thread pool
3. Worker thread picks up request from queue
4. Worker handles request, creating LMDB transactions as needed
5. Response sent and connection closed
6. Worker returns to wait for next request

### SSE (Server-Sent Events) Handling

Long-lived SSE connections are handled specially:
- Spawned as dedicated threads (not using the thread pool)
- Maintain persistent connections for real-time updates
- Cleaned up when client disconnects

## Usage Example

```zig
const std = @import("std");
const Storage = @import("storage/storage.zig").Storage;
const ThreadPoolHttpServer = @import("api/thread_pool_server.zig").ThreadPoolHttpServer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize storage
    var storage = try Storage.init(allocator, "data");
    defer storage.deinit();

    // Create server with 8 worker threads
    var server = try ThreadPoolHttpServer.init(allocator, &storage, 3000, 8);
    defer server.deinit();

    // Start server (blocks forever)
    try server.start();
}
```

## Configuration

The number of threads can be configured based on your needs:
- Default: 4 threads
- Recommended: Number of CPU cores
- Maximum: Limited by system resources

```zig
// Use default thread count
var server = try ThreadPoolHttpServer.init(allocator, &storage, 3000, null);

// Specify thread count
var server = try ThreadPoolHttpServer.init(allocator, &storage, 3000, 16);
```

## Performance Considerations

1. **Thread Pool Size**: More threads allow handling more concurrent requests but increase memory usage
2. **LMDB Map Size**: Ensure LMDB map size is sufficient for your data
3. **Connection Handling**: Each connection uses a thread from the pool briefly
4. **Memory Usage**: Each thread has its own stack allocation

## Migration from SimpleHttpServer

The ThreadPoolHttpServer is designed as a drop-in replacement:

```zig
// Before
var server = try SimpleHttpServer.init(allocator, &storage, 3000);

// After
var server = try ThreadPoolHttpServer.init(allocator, &storage, 3000, 8);
```

All existing methods (enableAuth, enableRules, etc.) work identically.

## Testing

Run thread pool tests:
```bash
zig test src/api/thread_pool_simple_test.zig
```

The thread pool implementation includes tests for:
- Basic initialization and shutdown
- Task submission and execution
- Concurrent request handling
- Proper cleanup on shutdown

## Future Enhancements

1. **Dynamic Thread Scaling**: Adjust thread count based on load
2. **Request Prioritization**: Handle high-priority requests first
3. **Connection Pooling**: Reuse connections for better performance
4. **Metrics**: Track thread utilization and request latency