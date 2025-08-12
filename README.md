# 🦌 Antler

> High-performance embedded tree database with Firebase RTDB semantics

[![Rust](https://img.shields.io/badge/rust-1.70%2B-orange.svg)](https://www.rust-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Performance](https://img.shields.io/badge/writes-17k%2Fsec-green.svg)]()
[![Performance](https://img.shields.io/badge/reads-5M%2Fsec-green.svg)]()

Antler is a blazingly fast, embedded tree database that implements Firebase Realtime Database semantics locally. Built in pure Rust with zero dependencies, it's perfect for applications needing hierarchical data storage with excellent performance.

## ✨ Features

- 🚀 **Extreme Performance** - 17,000+ writes/sec, 5,000,000+ reads/sec
- 🌲 **Tree Structure** - Native hierarchical data like Firebase RTDB
- 🔍 **Pattern Matching** - Wildcards (`*`, `?`) for flexible queries
- 📚 **Range Queries** - Efficient pagination and scanning
- 💾 **LSM Tree Architecture** - Log-structured merge tree with compaction
- 🔄 **Async Support** - Non-blocking operations with Tokio
- 🎯 **Zero Dependencies** - Pure Rust implementation (except optional async)
- 💪 **ACID Properties** - Atomic writes, crash recovery via WAL
- 📦 **Tiny Footprint** - ~60KB of Rust code

## 🚀 Quick Start

### Rust

```rust
use antler::Store;
use std::path::Path;

// Open or create a store
let store = Store::open(Path::new("./my_data"))?;

// Set values
store.set("users/alice/name", "Alice Smith", false)?;
store.set("users/alice/age", "30", false)?;

// Get values
let name = store.get("users/alice/name")?; // Some("Alice Smith")

// Get subtree as JSON
let users = store.get("users/")?; // {"alice": {"name": "Alice Smith", "age": "30"}}

// Pattern matching
let names = store.get_pattern("users/*/name")?; // All user names

// Range queries
let range = store.get_range("users/alice", "users/bob")?;
```

### Node.js (Coming Soon)

```javascript
const antler = require('@elkyn/antler');

// Open database
const db = antler.open('./my_data');

// Firebase-like API
await db.set('users/alice/name', 'Alice Smith');
const name = await db.get('users/alice/name');

// Get entire subtree
const users = await db.get('users/');
// Returns: { alice: { name: 'Alice Smith', age: '30' } }

// Pattern matching
const names = await db.getPattern('users/*/name');

// Range queries
const range = await db.getRange('users/alice', 'users/bob');
```

### CLI

```bash
# Install CLI
cargo install antler-cli

# Interactive shell
antler-cli

antler> set users/alice/name "Alice Smith"
antler> get users/
{
  "alice": {
    "name": "Alice Smith"
  }
}
antler> pattern users/*/name
Found 1 matches:
  users/alice/name = Alice Smith
```

## 🏗️ Architecture

Antler uses a sophisticated LSM (Log-Structured Merge) tree architecture:

```
┌─────────────┐
│   Writes    │
└──────┬──────┘
       ↓
┌─────────────┐
│  MemTable   │ In-memory B-tree (4MB)
└──────┬──────┘
       ↓ Flush
┌─────────────┐
│  L0 Segments│ Recent writes (4 segments max)
└──────┬──────┘
       ↓ Compact
┌─────────────┐
│  L1 Segments│ Merged data (10x larger)
└──────┬──────┘
       ↓ Compact
┌─────────────┐
│  L2 Segments│ Cold data (100x larger)
└─────────────┘
```

### Key Components

- **WAL (Write-Ahead Log)**: Ensures durability, survives crashes
- **MemTable**: Fast in-memory B-tree for recent writes
- **Segments**: Immutable sorted files with bloom filters
- **Compaction**: Background process merging and optimizing segments
- **Block Cache**: 32MB LRU cache for hot data

## 📊 Performance

Benchmarked on MacBook Pro M1:

| Operation | Performance | Latency (p99) |
|-----------|------------|---------------|
| Write | 17,000 ops/sec | 0.2ms |
| Read (cached) | 5,000,000 ops/sec | 0.001ms |
| Read (cold) | 277,000 ops/sec | 0.05ms |
| Range Query | 400,000 ops/sec | 0.01ms |
| Pattern Match | 50,000 ops/sec | 0.5ms |

### Benchmark Results

```bash
# Run benchmarks
cargo bench

# Results
test bench_writes        ... bench:      58,823 ns/iter (+/- 2,941)
test bench_reads_cached  ... bench:         200 ns/iter (+/- 10)
test bench_reads_cold    ... bench:       3,610 ns/iter (+/- 180)
test bench_range_query   ... bench:       2,500 ns/iter (+/- 125)
```

## 🌲 Tree Structure Rules

Like Firebase RTDB, Antler enforces tree structure rules:

1. **Leaf nodes** can only contain scalar values
2. **Parent nodes** cannot have both a value and children
3. **Path components** are separated by `/`

```rust
// ✅ Valid
store.set("config/server/host", "localhost", false)?;
store.set("config/server/port", "8080", false)?;

// ❌ Invalid - parent "config/server" has a scalar value
store.set("config/server", "value", false)?;
store.set("config/server/host", "localhost", false)?; // ERROR!

// ✅ Fix with replace_subtree flag
store.set("config/server/host", "localhost", true)?; // Replaces entire subtree
```

## 🔍 Pattern Matching

Powerful wildcard support for flexible queries:

```rust
// * matches any sequence of characters
let users = store.get_pattern("users/*/profile")?;
let logs = store.get_pattern("logs/2024/*")?;

// ? matches exactly one character  
let items = store.get_pattern("item?")?; // matches item1, item2, etc.

// Delete patterns
let deleted = store.delete_pattern("temp/*")?; // Clean up temp files
```

## 📖 API Reference

### Core Operations

```rust
// Open a store
Store::open(path: &Path) -> Result<Store>

// Basic CRUD
store.set(key: &str, value: &str, replace_subtree: bool) -> Result<()>
store.get(key: &str) -> Result<Option<String>>
store.delete(key: &str) -> Result<()>
store.delete_subtree(prefix: &str) -> Result<()>

// Pattern matching
store.get_pattern(pattern: &str) -> Result<Vec<(String, String)>>
store.delete_pattern(pattern: &str) -> Result<usize>

// Range queries
store.get_range(start: &str, end: &str) -> Result<Vec<(String, String)>>
store.get_range_limit(start: &str, end: &str, limit: usize) -> Result<Vec<(String, String)>>
store.scan_prefix(prefix: &str, limit: usize) -> Result<Vec<(String, String)>>

// Management
store.flush() -> Result<()>  // Force flush to disk
store.segment_counts() -> (usize, usize, usize)  // L0, L1, L2 counts
```

### Async API

```rust
use antler::AsyncStore;

let store = AsyncStore::open(path).await?;
store.set("key", "value", false).await?;
let value = store.get("key").await?;
```

## 🛠️ Installation

### Rust

Add to your `Cargo.toml`:

```toml
[dependencies]
antler = "0.1.0"

# For async support
antler = { version = "0.1.0", features = ["async"] }
```

### Node.js (Coming Soon)

```bash
npm install @elkyn/antler
```

### Build from Source

```bash
git clone https://github.com/elkyn/antler
cd antler
cargo build --release

# Run tests
cargo test

# Run benchmarks
cargo bench

# Build CLI
cargo build --release --bin antler-cli
```

## 📁 Storage Format

Antler stores data in an efficient binary format:

```
data/
├── wal.log           # Write-ahead log
├── manifest.log      # Segment registry
├── l0_0000001.seg   # L0 segment files
├── l1_0000001.seg   # L1 segment files
└── l2_0000001.seg   # L2 segment files
```

Each segment contains:
- Sorted key-value pairs
- Bloom filter for fast lookups
- Block index for efficient seeking
- Checksums for data integrity

## 🔄 Compaction

Automatic background compaction keeps performance optimal:

- **L0 → L1**: When L0 has >4 segments
- **L1 → L2**: When L1 has >10 segments
- Removes duplicates and deleted keys
- Merges overlapping key ranges
- Maintains sorted order for fast lookups

## 🚦 Examples

### Real-time Chat Application

```rust
// Store messages
store.set("rooms/general/msg1/text", "Hello!", false)?;
store.set("rooms/general/msg1/user", "alice", false)?;
store.set("rooms/general/msg1/timestamp", "1699999999", false)?;

// Get all messages in a room
let messages = store.get("rooms/general/")?;
// Returns hierarchical JSON with all messages

// Get recent messages (range query)
let recent = store.get_range_limit(
    "rooms/general/msg100",
    "rooms/general/msg200", 
    50
)?;
```

### User Management System

```rust
// Create user
store.set("users/alice/email", "alice@example.com", false)?;
store.set("users/alice/role", "admin", false)?;
store.set("users/alice/created", "2024-01-01", false)?;

// Find all admins
let admins = store.get_pattern("users/*/role")?
    .into_iter()
    .filter(|(_, role)| role == "admin")
    .collect::<Vec<_>>();

// Delete user and all data
store.delete_subtree("users/alice/")?;
```

### Configuration Management

```rust
// Store config
store.set("config/db/host", "localhost", false)?;
store.set("config/db/port", "5432", false)?;
store.set("config/cache/ttl", "3600", false)?;

// Get entire config
let config = store.get("config/")?;
// Returns: {"db": {"host": "localhost", "port": "5432"}, "cache": {"ttl": "3600"}}

// Update entire section atomically
store.set("config/db", "{...}", true)?; // replace_subtree = true
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by [Firebase Realtime Database](https://firebase.google.com/docs/database)
- LSM tree design influenced by [RocksDB](https://rocksdb.org/)
- Built with [Rust](https://www.rust-lang.org/) 🦀

## 📮 Contact

- GitHub: [@elkyn](https://github.com/elkyn)
- npm: [@elkyn/antler](https://www.npmjs.com/package/@elkyn/antler)

---

Made with ❤️ and 🦀 by the Elkyn team