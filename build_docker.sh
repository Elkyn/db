#!/bin/bash
set -e

echo "🐳 Building Elkyn DB Linux binaries with Docker..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p dist

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is required but not installed${NC}"
    exit 1
fi

# Create Dockerfile
cat > Dockerfile.build << 'EOF'
FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    liblmdb-dev \
    build-essential \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Zig 0.13.0 (stable release)
RUN curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar -xJ && \
    mv zig-linux-x86_64-0.13.0 /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig

WORKDIR /build
COPY . .

# Find LMDB and build
RUN pkg-config --libs --cflags lmdb && \
    ls -la /usr/lib/x86_64-linux-gnu/ | grep lmdb || true && \
    ls -la /usr/include/ | grep lmdb || true && \
    export LIBRARY_PATH=/usr/lib/x86_64-linux-gnu && \
    export C_INCLUDE_PATH=/usr/include && \
    zig build -Doptimize=ReleaseFast
EOF

# Build for Linux x86_64
echo -e "${BLUE}Building Linux x86_64 with Docker...${NC}"
docker build --platform linux/amd64 -f Dockerfile.build -t elkyn-build . || {
    echo -e "${RED}Docker build failed${NC}"
    rm -f Dockerfile.build
    exit 1
}

# Extract binaries
echo -e "${BLUE}Extracting binaries...${NC}"
docker create --name elkyn-extract elkyn-build
docker cp elkyn-extract:/build/zig-out/bin/elkyn-server dist/elkyn-server-linux-x86_64
docker cp elkyn-extract:/build/zig-out/bin/elkyn-db dist/elkyn-db-linux-x86_64
docker cp elkyn-extract:/build/zig-out/lib/libelkyn-embedded.so dist/libelkyn-embedded-linux-x86_64.so 2>/dev/null || true
docker rm elkyn-extract

# Cleanup
docker rmi elkyn-build
rm -f Dockerfile.build

echo -e "${GREEN}✓ Built Linux x86_64 binaries${NC}"

# Also build native if on macOS
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo -e "${BLUE}Building native macOS binaries...${NC}"
    zig build -Doptimize=ReleaseFast || {
        echo -e "${YELLOW}Warning: Native build failed${NC}"
    }
    
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        cp zig-out/bin/elkyn-server dist/elkyn-server-macos-arm64 2>/dev/null || true
        cp zig-out/bin/elkyn-db dist/elkyn-db-macos-arm64 2>/dev/null || true
        cp zig-out/lib/libelkyn-embedded.dylib dist/ 2>/dev/null || true
        echo -e "${GREEN}✓ Built macOS ARM64 (native)${NC}"
    fi
fi

echo -e "${BLUE}Build complete! Binaries in dist/${NC}"
ls -lh dist/

# Create checksums
echo -e "${BLUE}Creating checksums...${NC}"
cd dist
if command -v shasum &> /dev/null; then
    find . -maxdepth 1 -type f -exec shasum -a 256 {} \; > checksums.sha256
else
    find . -maxdepth 1 -type f -exec sha256sum {} \; > checksums.sha256
fi
cd ..
echo -e "${GREEN}✓ Checksums created${NC}"

echo -e "${GREEN}✨ All done!${NC}"
echo ""
echo -e "${YELLOW}Note: Linux binaries require LMDB on target system:${NC}"
echo -e "${YELLOW}  Ubuntu/Debian: sudo apt install liblmdb0${NC}"
echo -e "${YELLOW}  RHEL/CentOS: sudo yum install lmdb${NC}"