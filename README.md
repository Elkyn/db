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

### Phase 4: Authentication & Rules Engine ✅
- [x] JWT token validation (HS256)
- [x] Token generation endpoint for testing
- [x] Auth context in request handlers
- [x] Web UI authentication integration
- [x] Rule parser and compiler
- [x] Rule evaluation engine with cascading
- [x] Path variable substitution ($userId, etc)
- [ ] Cross-reference resolution (root.path.to.data)
- [x] Unit tests for auth

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

### Server Mode (@elkyn/realtime-db)

```bash
# Build and run server
zig build -Doptimize=ReleaseFast
./start.sh

# Access the web dashboard
open http://localhost:8889/index.html
```

### Embedded Mode (@elkyn/store)

```bash
# Build Node.js bindings
./build_nodejs.sh

# Use in your Node.js app
cd nodejs-bindings
npm test
```

```javascript
const { ElkynStore } = require('@elkyn/store');

const store = new ElkynStore('./data');
store.enableAuth('secret');
store.setupDefaultRules();

const token = store.createToken('user123');
store.set('/users/user123/profile', { name: 'Alice' }, token);

const profile = store.get('/users/user123/profile', token);
console.log(profile); // { name: 'Alice' }

store.close();
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

// With Authentication
// First get a token
const tokenResp = await fetch('http://localhost:9000/auth/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ uid: 'user123', email: 'user@example.com' })
});
const { token } = await tokenResp.json();

// Use token in requests
await fetch('http://localhost:9000/users/123', {
  method: 'PUT',
  headers: { 
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`
  },
  body: JSON.stringify({ name: 'Alice' })
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