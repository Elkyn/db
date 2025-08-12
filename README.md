# @elkyn/antler

A high-performance, Firebase RTDB-like tree store written in Rust.

## Features

- **Tree-structured data** with leaf-only scalar values
- **LSM-tree architecture** with WAL and tiered segments
- **Bloom filters** for fast non-existence proofs
- **Block cache** for hot data
- **Group commit** for write batching
- **Crash-safe** with manifest-based recovery
- **Thread-safe** concurrent reads
- **Subtree operations** with prefix tombstones

## Performance

On a modern laptop (1000 operations):
- **Writes**: ~4,000 ops/sec
- **Reads**: ~120,000 ops/sec
- **Storage**: Efficient with optional compression

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
┌──────▼──────┐
│     WAL     │ ← Group commit every 10ms
└──────┬──────┘
       │
┌──────▼──────┐
│  MemTable   │ ← In-memory BTree
└──────┬──────┘
       │ Flush at 256KB
┌──────▼──────┐
│  L0 Segment │ ← Immutable SSTable files
├─────────────┤   with bloom filters
│  L1 Segment │
├─────────────┤
│  L2 Segment │
└─────────────┘
```

## Usage

```bash
# Build
rustc -O antler.rs -o antler

# Run
./antler /path/to/data

# Commands
set path/to/key value          # Set a value
set-r path/to/key value        # Replace subtree
get path/to/key                # Get a value
get path/to/                   # Get subtree as JSON
del path/to/key                # Delete a key
del-sub path/to/                # Delete subtree
flush                          # Force flush to disk
exit                           # Clean shutdown
```

## Design Principles

1. **Leaf-only values**: Only leaf nodes can contain scalar values
2. **Write-ahead logging**: All mutations logged before applying
3. **Copy-on-write**: Segments are immutable once written
4. **Crash recovery**: Manifest tracks all segments atomically
5. **Firebase semantics**: Parent/child validation, subtree operations

## Implementation Details

- **Segments**: Immutable SSTable files with index + bloom filter
- **Bloom filters**: 10 bits/key, 7 hash functions, ~1% false positive
- **Block size**: 4KB blocks for efficient I/O
- **Cache**: 32MB LRU block cache
- **WAL**: CRC32-protected records, group commit every 10ms
- **Manifest**: Simple pipe-delimited format for crash recovery

## License

MIT

## Contributing

This is an open-source project by Elkyn. Contributions welcome!

---

Built with focus on correctness, performance, and simplicity.