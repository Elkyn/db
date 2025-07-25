#!/bin/bash
set -e

echo "🚀 Building Elkyn DB for current platform only..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p dist

# Clean previous builds
rm -rf zig-out dist/*

echo -e "${YELLOW}⚠️  Note: Using system LMDB - only native builds possible${NC}"
echo -e "${YELLOW}   Cross-compilation requires bundling LMDB source${NC}"
echo ""

# Build for current platform (native)
echo -e "${BLUE}Building native (optimized for current CPU)...${NC}"
zig build -Doptimize=ReleaseFast

# Detect current platform
OS=$(uname -s)
ARCH=$(uname -m)

if [[ "$OS" == "Darwin" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
        cp zig-out/bin/elkyn-server dist/elkyn-server-macos-arm64
        cp zig-out/bin/elkyn-db dist/elkyn-db-macos-arm64
        echo -e "${GREEN}✓ Built macOS ARM64 (native)${NC}"
    else
        cp zig-out/bin/elkyn-server dist/elkyn-server-macos-x86_64
        cp zig-out/bin/elkyn-db dist/elkyn-db-macos-x86_64
        echo -e "${GREEN}✓ Built macOS x86_64 (native)${NC}"
    fi
elif [[ "$OS" == "Linux" ]]; then
    if [[ "$ARCH" == "aarch64" ]]; then
        cp zig-out/bin/elkyn-server dist/elkyn-server-linux-arm64
        cp zig-out/bin/elkyn-db dist/elkyn-db-linux-arm64
        echo -e "${GREEN}✓ Built Linux ARM64 (native)${NC}"
    else
        cp zig-out/bin/elkyn-server dist/elkyn-server-linux-x86_64
        cp zig-out/bin/elkyn-db dist/elkyn-db-linux-x86_64
        echo -e "${GREEN}✓ Built Linux x86_64 (native)${NC}"
    fi
fi

# Also copy shared library if it exists
cp zig-out/lib/libelkyn-embedded.* dist/ 2>/dev/null || true

echo -e "${BLUE}Build complete! Native binary in dist/${NC}"
echo -e "${BLUE}Files created:${NC}"
ls -lh dist/

# Create checksums
echo -e "${BLUE}Creating checksums...${NC}"
cd dist
shasum -a 256 * > checksums.sha256
cd ..
echo -e "${GREEN}✓ Checksums created${NC}"

echo -e "${GREEN}✨ Done!${NC}"
echo ""
echo -e "${YELLOW}For cross-platform builds, consider:${NC}"
echo -e "${YELLOW}1. Using GitHub Actions with native runners${NC}"
echo -e "${YELLOW}2. Bundling LMDB source code${NC}"
echo -e "${YELLOW}3. Building on each target platform${NC}"