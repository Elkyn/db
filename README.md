# Elkyn DB

A blazing-fast, real-time tree database with declarative security rules. Think Firebase Realtime Database, but embedded, faster, and open source.

## Features

- 🌳 **Tree-structured data** - Intuitive path-based organization
- ⚡ **Sub-500ms boot time** - Built with Zig for maximum performance  
- 🔄 **Real-time subscriptions** - Live updates via WebSocket
- 🔒 **JWT-based auth** - Declarative security rules
- 💾 **LMDB storage** - ACID compliant, crash-safe
- 🧪 **100% test coverage** - Reliability first

## MVP Roadmap

### Phase 1: Core Storage Engine ✅
- [x] Project structure setup
- [x] LMDB wrapper with tree operations
- [x] Path-based key encoding  
- [x] Basic CRUD operations
- [x] Unit tests for storage layer
- [x] Storage integration layer (combine LMDB + tree)
- [x] JSON value serialization
- [x] Tree expansion for nested objects
- [x] Branch node reconstruction
- [x] Recursive delete with cursor iteration

### Phase 2: Real-time Event System & API ✅
- [x] Event emitter with Observable pattern
- [x] WebSocket server with proper frame handling
- [x] HTTP/REST endpoints (GET, PUT, PATCH, DELETE)
- [x] Subscription management
- [x] Path pattern matching for wildcards
- [x] Event filtering (basic implementation)
- [x] Basic error handling
- [x] Unit tests for real-time system
- [x] Storage integration with event emitter
- [x] Main server structure with graceful shutdown
- [x] WebSocket upgrade from HTTP
- [x] Real-time event delivery over WebSocket

### Phase 3: Demo Web Client 🎯
- [ ] Simple HTML/JS demo page
- [ ] WebSocket connection handling
- [ ] Real-time data display
- [ ] CRUD operations UI
- [ ] Tree visualization
- [ ] Live subscription demo
- [ ] Basic performance metrics

### Phase 4: Authentication & Rules Engine 🔒
- [ ] JWT token validation (RS256/HS256)
- [ ] Rule parser and compiler
- [ ] Rule evaluation engine (comptime optimized)
- [ ] Path variable substitution ($userId, etc)
- [ ] Cross-reference resolution (root.path.to.data)
- [ ] Unit tests for auth & rules

### Phase 5: Client SDK & DevEx 📦
- [ ] TypeScript client library
- [ ] Auto-reconnection logic
- [ ] Optimistic updates
- [ ] Offline queue
- [ ] Developer-friendly error messages
- [ ] JSON path queries
- [ ] Batch operations

### Phase 6: Production Ready 🚀
- [ ] Docker image (<50MB)
- [ ] S3 backup integration
- [ ] Monitoring endpoints
- [ ] Performance benchmarks
- [ ] Documentation site

## Quick Start

```bash
# Run with Docker
docker run -p 9000:9000 -v ./data:/data elkyn/elkyn-db

# Or build from source
zig build -Doptimize=ReleaseFast
./zig-out/bin/elkyn-db --port 9000 --data ./data
```

## Example Usage

```javascript
// Connect
const db = new ElkynDB('ws://localhost:9000', {
  auth: 'your-jwt-token'
});

// Write data
await db.set('/users/123', {
  name: 'Alice',
  email: 'alice@example.com'
});

// Subscribe to changes
db.subscribe('/users/*', (change) => {
  console.log('User changed:', change);
});

// Query with filters
const adults = await db.query('/users/*[?age>=18]');
```

## Rules Example

```json
{
  "rules": {
    "users": {
      "$userId": {
        ".read": "$userId === auth.uid || auth.admin === true",
        ".write": "$userId === auth.uid",
        "email": {
          ".read": "$userId === auth.uid"
        }
      }
    }
  }
}
```

## Architecture

```
┌─────────────────┐     ┌──────────────┐
│   Zap HTTP/WS   │────▶│  JWT Auth    │
└────────┬────────┘     └──────┬───────┘
         │                     │
┌────────▼────────┐     ┌──────▼───────┐
│  Rule Engine    │────▶│ Event System │
│  (Comptime)     │     │ (Observable) │
└────────┬────────┘     └──────────────┘
         │
┌────────▼────────┐
│      LMDB       │
│  (Tree Storage) │
└─────────────────┘
```

## Contributing

We welcome contributions! Please ensure:
- All code has unit tests
- Tests pass: `zig build test`
- Follow the style guide in CLAUDE.md

## License

MIT