# Memory Safety in Elkyn DB Event System

## Overview

The event system bridges Zig (manual memory management) with JavaScript (garbage collection), requiring careful attention to memory safety.

## Key Memory Safety Measures

### 1. Zig Side (EventQueue)

- **Fixed-size arrays**: Path data uses fixed 256-byte arrays instead of slices to avoid lifetime issues
- **Ring buffer**: Lock-free SPSC design with fixed capacity prevents unbounded growth
- **Value buffer**: Separate 1MB buffer for variable-length data with wraparound
- **No allocations in hot path**: All memory is pre-allocated during init

### 2. C API Bridge

- **Deep copies**: Event data is duplicated before passing to N-API callbacks
- **Proper cleanup**: Original strings freed after all listeners processed
- **Thread safety**: Event thread properly joins on shutdown

### 3. JavaScript Side

- **Automatic cleanup**: Subscriptions tracked and cleaned on unsubscribe
- **WeakMap prevention**: No long-lived references to prevent GC issues
- **Observable chains**: Each operator creates new subscription, properly chained

## Memory Leak Testing

### JavaScript Tests
```bash
# Run with GC control
node --expose-gc test_memory_leaks.js

# Monitor specific scenarios
node --expose-gc monitor_memory.js
```

### Zig Tests
```bash
# Run with leak detection
zig test src/test_memory_simple.zig

# Run comprehensive tests
zig build-exe src/test_event_memory.zig && ./test_event_memory
```

### Valgrind (Linux)
```bash
./test_valgrind.sh
```

## Common Leak Patterns to Avoid

1. **Forgotten unsubscribe**: Always unsubscribe when done
   ```javascript
   const sub = store.watch('/path').subscribe(handler);
   // ... later ...
   sub.unsubscribe(); // Don't forget!
   ```

2. **Circular references**: Avoid storing event objects
   ```javascript
   // Bad - keeps reference to event
   const events = [];
   store.watch('/*').subscribe(e => events.push(e));
   
   // Good - extract only needed data
   const paths = [];
   store.watch('/*').subscribe(e => paths.push(e.path));
   ```

3. **Long-running subscriptions**: Consider using `take()` or `debounce()`
   ```javascript
   // Automatically unsubscribe after 10 events
   store.watch('/*').take(10).subscribe(handler);
   ```

## Memory Monitoring in Production

1. **Node.js metrics**:
   ```javascript
   setInterval(() => {
       const mem = process.memoryUsage();
       console.log('Memory:', {
           rss: (mem.rss / 1024 / 1024).toFixed(2) + ' MB',
           heap: (mem.heapUsed / 1024 / 1024).toFixed(2) + ' MB'
       });
   }, 60000);
   ```

2. **Event queue monitoring**:
   ```javascript
   // Built-in queue metrics (to be implemented)
   store.getEventQueueStats(); // { pending: 0, processed: 1234 }
   ```

## Best Practices

1. **Always close stores**: Call `store.close()` when done
2. **Unsubscribe properly**: Track and clean up all subscriptions
3. **Avoid large payloads**: Keep event data reasonable (<1MB)
4. **Use batching**: Process events in batches for better memory usage
5. **Monitor production**: Set up alerts for memory growth

## Implementation Details

### EventQueue Memory Layout
- Events ring buffer: 1024 × ~300 bytes ≈ 300KB
- Value buffer: 1MB circular buffer
- Total per queue: ~1.3MB fixed allocation

### Event Flow
1. Storage → EventEmitter (Zig heap)
2. EventEmitter → EventQueue (pre-allocated)
3. EventQueue → C++ (deep copy with new/delete)
4. C++ → JavaScript (N-API manages lifetime)

### Cleanup Chain
1. JavaScript: `subscription.unsubscribe()`
2. C++: `napi_release_threadsafe_function()`
3. C++: `delete[]` for deep-copied strings
4. Zig: EventQueue buffers reused (no cleanup needed)
5. Store close: Thread join → EventQueue deinit → Free 1.3MB