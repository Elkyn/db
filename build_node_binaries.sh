#!/bin/bash
set -e

echo "🏗️  Building Node.js binaries for GitHub release..."

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Base directory
BASE_DIR=$(pwd)
BINDINGS_DIR="$BASE_DIR/nodejs-bindings"
OUTPUT_DIR="$BASE_DIR/dist/node"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to build native module
build_native() {
    local SUFFIX=$1
    echo -e "${BLUE}Building Node.js module for $SUFFIX...${NC}"
    
    # Build Zig library (includes static library)
    cd "$BASE_DIR"
    zig build -Doptimize=ReleaseFast
    
    # Build Node.js module
    cd "$BINDINGS_DIR"
    
    # Clean and build
    rm -rf build
    npm ci --ignore-scripts
    npm run build
    
    # Copy built module
    if [[ -f "build/Release/elkyn_store.node" ]]; then
        cp build/Release/elkyn_store.node "$OUTPUT_DIR/elkyn_store-$SUFFIX.node"
        echo -e "${GREEN}✓ Built $SUFFIX${NC}"
    else
        echo -e "${RED}Failed to build $SUFFIX${NC}"
        return 1
    fi
}

# Build Linux binaries with Docker if on macOS
if [[ "$(uname -s)" == "Darwin" ]] && command -v docker &> /dev/null; then
    echo -e "${BLUE}Building Linux Node.js binaries with Docker...${NC}"
    
    # Create Dockerfile
    cat > "$BASE_DIR/Dockerfile.node" << 'EOF'
FROM node:18-bookworm

# Install build dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    liblmdb-dev \
    pkg-config \
    curl \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
RUN curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar -xJ && \
    mv zig-linux-x86_64-0.13.0 /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig

WORKDIR /build
COPY . .

# Build Zig library (includes static library)
RUN zig build -Doptimize=ReleaseFast

# Build Node.js module
WORKDIR /build/nodejs-bindings
RUN npm ci --ignore-scripts
RUN npm run build

# Copy the built module
RUN cp build/Release/elkyn_store.node /elkyn_store-linux-x64.node
EOF

    # Build with Docker
    docker build --platform linux/amd64 -f Dockerfile.node -t elkyn-node-build . || {
        echo -e "${YELLOW}Warning: Docker build failed${NC}"
    }
    
    # Extract binary
    docker create --name elkyn-node-extract elkyn-node-build
    docker cp elkyn-node-extract:/elkyn_store-linux-x64.node "$OUTPUT_DIR/elkyn_store-linux-x64.node" || true
    docker rm elkyn-node-extract
    docker rmi elkyn-node-build
    rm -f Dockerfile.node
    
    if [[ -f "$OUTPUT_DIR/elkyn_store-linux-x64.node" ]]; then
        echo -e "${GREEN}✓ Built Linux x64 Node.js module${NC}"
    fi
fi

# Build native module
OS=$(uname -s)
ARCH=$(uname -m)

if [[ "$OS" == "Darwin" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
        build_native "darwin-arm64"
    else
        build_native "darwin-x64"
    fi
elif [[ "$OS" == "Linux" ]]; then
    if [[ "$ARCH" == "aarch64" ]]; then
        build_native "linux-arm64"
    else
        build_native "linux-x64"
    fi
fi

echo -e "${BLUE}Node.js binaries built:${NC}"
ls -la "$OUTPUT_DIR"

echo -e "${GREEN}✨ Done!${NC}"
echo ""
echo -e "${BLUE}To add to GitHub release:${NC}"
echo "  gh release upload <tag> dist/node/*.node"
echo ""
echo -e "${BLUE}Or include in create_release.sh${NC}"