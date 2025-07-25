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

# Function to create Dockerfile for specific architecture
create_dockerfile() {
    local ARCH=$1
    local ZIG_ARCH=$2
    local LIB_ARCH=$3
    
    cat > Dockerfile.build << EOF
FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    liblmdb-dev \
    build-essential \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Zig 0.13.0 for the target architecture
RUN curl -L https://ziglang.org/download/0.13.0/zig-linux-${ZIG_ARCH}-0.13.0.tar.xz | tar -xJ && \
    mv zig-linux-${ZIG_ARCH}-0.13.0 /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig

WORKDIR /build
COPY . .

# Find LMDB and build
RUN echo "Setting up LMDB for ${LIB_ARCH}..." && \\
    pkg-config --libs --cflags lmdb && \\
    find /usr/lib -name "liblmdb*" && \\
    ln -sf /usr/lib/${LIB_ARCH}/liblmdb.so /usr/lib/liblmdb.so && \\
    ln -sf /usr/lib/${LIB_ARCH}/liblmdb.a /usr/lib/liblmdb.a && \\
    ls -la /usr/lib/liblmdb* && \\
    export LIBRARY_PATH=/usr/lib/${LIB_ARCH}:/usr/lib && \\
    export C_INCLUDE_PATH=/usr/include && \\
    export PKG_CONFIG_PATH=/usr/lib/${LIB_ARCH}/pkgconfig && \\
    zig build -Doptimize=ReleaseFast
EOF
}

# Build for Linux x86_64
echo -e "${BLUE}Building Linux x86_64 with Docker...${NC}"
create_dockerfile "amd64" "x86_64" "x86_64-linux-gnu"
docker build --platform linux/amd64 -f Dockerfile.build -t elkyn-build-amd64 . || {
    echo -e "${RED}Docker build failed${NC}"
    rm -f Dockerfile.build
    exit 1
}

# Extract x86_64 binaries
echo -e "${BLUE}Extracting x86_64 binaries...${NC}"
docker create --name elkyn-extract-amd64 elkyn-build-amd64
docker cp elkyn-extract-amd64:/build/zig-out/bin/elkyn-server dist/elkyn-server-linux-x86_64
docker cp elkyn-extract-amd64:/build/zig-out/bin/elkyn-db dist/elkyn-db-linux-x86_64
docker cp elkyn-extract-amd64:/build/zig-out/lib/libelkyn-embedded.so dist/libelkyn-embedded-linux-x86_64.so 2>/dev/null || true
docker rm elkyn-extract-amd64
docker rmi elkyn-build-amd64

# Build for Linux ARM64
echo -e "${BLUE}Building Linux ARM64 with Docker...${NC}"
create_dockerfile "arm64" "aarch64" "aarch64-linux-gnu"
docker build --platform linux/arm64 -f Dockerfile.build -t elkyn-build-arm64 . || {
    echo -e "${YELLOW}Warning: ARM64 build failed - this is optional${NC}"
}

# Extract ARM64 binaries if build succeeded
if docker image inspect elkyn-build-arm64 >/dev/null 2>&1; then
    echo -e "${BLUE}Extracting ARM64 binaries...${NC}"
    docker create --name elkyn-extract-arm64 elkyn-build-arm64
    docker cp elkyn-extract-arm64:/build/zig-out/bin/elkyn-server dist/elkyn-server-linux-arm64
    docker cp elkyn-extract-arm64:/build/zig-out/bin/elkyn-db dist/elkyn-db-linux-arm64
    docker cp elkyn-extract-arm64:/build/zig-out/lib/libelkyn-embedded.so dist/libelkyn-embedded-linux-arm64.so 2>/dev/null || true
    docker rm elkyn-extract-arm64
    docker rmi elkyn-build-arm64
    echo -e "${GREEN}✓ Built Linux ARM64 binaries${NC}"
fi

# Cleanup
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