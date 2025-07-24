# Elkyn DB

A blazing-fast, real-time tree database with declarative security rules. Think Firebase Realtime Database, but embedded, faster, and open source.

## Features

### Current
- 🌳 **Tree-structured data** - Intuitive path-based organization
- ⚡ **Sub-2ms boot time** - Built with Zig for maximum performance  
- 🔄 **Real-time subscriptions** - Live updates via Server-Sent Events (SSE)
- 🔒 **JWT-based auth** - Declarative security rules with cascading
- 💾 **LMDB storage** - ACID compliant, crash-safe persistence
- 🧵 **Multi-threading** - Concurrent request handling with thread pool
- 📦 **Dual deployment** - Server mode or embedded Node.js library
- 🗜️ **MessagePack** - Efficient binary serialization

### Coming Soon
- 🌐 **Distributed clusters** - Master-slave replication with automatic failover
- 📱 **Offline support** - Standalone mode for offline-first applications
- 🔊 **Real-time events in Node.js** - Native event callbacks for embedded mode
- 📊 **Production logging** - Structured logs with configurable levels

## Roadmap

### ✅ Completed
- **Core Storage Engine** - LMDB-backed tree storage with ACID guarantees
- **Real-time API** - REST endpoints with Server-Sent Events
- **Security Rules** - Firebase-compatible rule engine with path variables
- **JWT Authentication** - Token-based auth with role support
- **Web Dashboard** - Interactive UI for testing and monitoring
- **Multi-threading** - Thread pool for concurrent request handling
- **MessagePack** - Binary serialization for 50% size reduction
- **Dual Architecture** - Server mode and embedded Node.js library

### 🚧 In Progress

#### Phase 1: Critical Fixes
- [ ] **Node.js Real-time Events** - Fix event system for embedded mode
- [ ] **Production Logging** - Structured logs with levels and audit trail

#### Phase 2: Distributed Architecture
- [ ] **Binary Protocol** - Custom TCP protocol for inter-node communication
- [ ] **Cluster Formation** - Node discovery and gossip protocol
- [ ] **OpLog Replication** - Change tracking and replay mechanism
- [ ] **Master-Slave** - Read replicas with automatic sync
- [ ] **Leader Election** - Raft consensus for automatic failover

#### Phase 3: Embedded Modes
- [ ] **Standalone Mode** - Fully local database for offline apps
- [ ] **Embedded Replicas** - Read-only mode with cluster connection
- [ ] **Memory-Only Option** - Pure RAM storage for caching
- [ ] **Partial Replication** - Subscribe to specific paths only

#### Phase 4: Operations
- [ ] **CLI Tool** - Cluster management and data operations
- [ ] **Backup System** - Snapshots and continuous OpLog streaming
- [ ] **Monitoring** - Metrics, health checks, and alerts
- [ ] **Migration Tools** - Import/export from other databases

### 🔮 Future
- **TypeScript SDK** - First-class client library
- **GraphQL Support** - Alternative query interface
- **Multi-Region** - Geographic distribution
- **CRDT Support** - Conflict-free data types
- **WebAssembly** - Browser-native embedded mode

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

# Install in your project
cd nodejs-bindings
npm link

# Use in your app
npm link @elkyn/store
```

```javascript
const { ElkynStore } = require('@elkyn/store');

// Standalone mode - fully local
const localStore = new ElkynStore({ mode: 'standalone' });
localStore.set('/users/123', { name: 'Alice' });

// Embedded mode - connects to cluster (coming soon)
const store = new ElkynStore({ 
  mode: 'embedded',
  clusterUrl: 'tcp://db.myapp.com:7889'
});

// With authentication
store.enableAuth('secret');
store.setupDefaultRules();

const token = store.createToken('user123');
store.set('/users/user123/profile', { name: 'Alice' }, token);

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

### Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Elkyn DB Core (Zig)                      │
├─────────────────────────────┬───────────────────────────────┤
│   Server Mode               │   Embedded Mode               │
│   (@elkyn/realtime-db)      │   (@elkyn/store)             │
├─────────────────────────────┼───────────────────────────────┤
│ • HTTP/REST API             │ • Node.js C++ Bindings       │
│ • Server-Sent Events        │ • Direct Storage Access      │
│ • Multi-threading           │ • In-Process Operation       │
│ • Web Dashboard             │ • Zero Network Overhead      │
└─────────────────────────────┴───────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                    Shared Components                         │
├─────────────────────────────────────────────────────────────┤
│ • LMDB Storage Engine       │ • Security Rules Engine      │
│ • Tree Operations           │ • JWT Authentication         │
│ • MessagePack Serialization │ • Event System               │
└─────────────────────────────────────────────────────────────┘
```

### Planned Distributed Architecture

```
┌─────────────┐     OpLog      ┌─────────────┐
│   Master    │◀──────────────▶│   Slave 1   │
│  (Primary)  │                 │ (Read Only) │
└──────┬──────┘                 └─────────────┘
       │                               │
       │         Raft Leader           │
       │          Election             │
       ▼                               ▼
┌─────────────┐                 ┌─────────────┐
│   Slave 2   │                 │  Embedded   │
│ (Read Only) │                 │   Node.js   │
└─────────────┘                 └─────────────┘

Features:
• Automatic failover with Raft consensus
• OpLog-based replication
• Read scaling with slave nodes
• Embedded nodes as read replicas
```

## Contributing

We welcome contributions! Please ensure:
- All code has unit tests
- Tests pass: `zig build test`
- Follow the style guide in CLAUDE.md

## License

MIT