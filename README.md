# Elkyn DB

A blazing-fast, real-time tree database with declarative security rules. Think Firebase Realtime Database, but embedded, faster, and open source.

## Features

- 🌳 **Tree-structured data** - Intuitive path-based organization
- ⚡ **Sub-500ms boot time** - Built with Zig for maximum performance  
- 🔄 **Real-time subscriptions** - Live updates via Server-Sent Events (SSE)
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
- [x] Server-Sent Events (SSE) for real-time updates
- [x] HTTP/REST endpoints (GET, PUT, DELETE)
- [x] Subscription management
- [x] Path pattern matching for wildcards
- [x] Event filtering (basic implementation)
- [x] Basic error handling
- [x] Unit tests for real-time system
- [x] Storage integration with event emitter
- [x] Main server structure
- [x] Real-time event delivery over SSE
- [x] Node-specific watching (watch /products, get only product updates)

### Phase 3: Demo Web Client ✅
- [x] Interactive web dashboard (served at /index.html)
- [x] SSE connection handling with EventSource API
- [x] Real-time data display with live updates
- [x] CRUD operations UI (GET, PUT, DELETE)
- [x] Tree visualization in Data Explorer
- [x] Live subscription demo with multiple watchers
- [x] Event log showing all real-time updates

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
# Build from source
zig build -Doptimize=ReleaseFast

# Run the server
./zig-out/bin/elkyn-server 9000 ./data

# Or with default settings (port 8080, ./data directory)
./zig-out/bin/elkyn-server

# Access the web dashboard
open http://localhost:9000/index.html
```

## Example Usage

```javascript
// REST API
await fetch('http://localhost:9000/users/123', {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: 'Alice',
    email: 'alice@example.com'
  })
});

// Subscribe to changes via SSE
const events = new EventSource('http://localhost:9000/users/.watch');
events.onmessage = (event) => {
  console.log('Users changed:', JSON.parse(event.data));
};

// Or use the web dashboard
// Open http://localhost:9000/index.html in your browser
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