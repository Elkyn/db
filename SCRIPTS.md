# Elkyn DB Scripts Guide

## 🚀 Release Process

To release a new version, simply run:
```bash
./release.sh
```

This will:
1. Update version numbers across all files
2. Commit version changes
3. Create and push git tag
4. Build all binaries (server + Node.js)
5. Create GitHub release with artifacts
6. Publish npm package

## 📦 Individual Scripts

### Release Scripts
- **`release.sh`** - Complete release automation
- **`update_version.sh`** - Update version in all files
- **`create_release.sh`** - Create GitHub release with binaries

### Build Scripts
- **`build_docker.sh`** - Build Linux binaries using Docker (for cross-platform)
- **`build_native.sh`** - Build binaries for current platform only
- **`build_node_binaries.sh`** - Build Node.js native modules

### Development Scripts
- **`dev.sh`** - Quick development server (auto-rebuild, port 8889)
- **`start.sh [port] [data_dir]`** - Production server launcher

## 🔧 Common Tasks

### Build for current platform
```bash
./build_native.sh
```

### Build Linux binaries on macOS
```bash
./build_docker.sh
```
This builds both x86_64 and ARM64 Linux binaries using Docker.

### Start development server
```bash
./dev.sh
```

### Create a release
```bash
./release.sh
```

### Update version only
```bash
./update_version.sh 0.2.0
```

## 📁 Build Outputs

- `dist/` - Server binaries
  - `elkyn-server-*` - HTTP server binaries (linux-x86_64, linux-arm64, macos-arm64, etc.)
  - `elkyn-db-*` - CLI binaries
  - `libelkyn-embedded.*` - Shared libraries
- `dist/node/` - Node.js binaries
  - `elkyn_store-*.node` - Native Node.js modules (linux-x64, linux-arm64, darwin-arm64, etc.)
- `zig-out/` - Raw build output

## 🐳 Docker Requirements

For cross-platform builds:
- Docker Desktop installed
- Linux containers enabled

## 📝 Notes

- All scripts use system LMDB linking
- Linux binaries require `liblmdb0` at runtime
- macOS binaries require `brew install lmdb`
- Node.js binaries are fetched from GitHub releases during npm install