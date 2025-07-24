#!/bin/bash

set -e

echo "🔧 Building Elkyn DB with Node.js bindings..."

# Build Zig libraries
echo "Building Zig libraries..."
zig build -Doptimize=ReleaseFast

# Check if required files exist
if [ ! -f "zig-out/lib/libelkyn-embedded-static.a" ]; then
    echo "❌ Static library not found!"
    exit 1
fi

echo "✅ Zig libraries built successfully"

# Build Node.js bindings
echo "Building Node.js bindings..."
cd nodejs-bindings

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing Node.js dependencies..."
    npm install node-gyp napi-macros
fi

# Build the native module
echo "Compiling native bindings..."
npx node-gyp rebuild

echo "✅ Node.js bindings built successfully"

# Run tests
if [ "$1" = "test" ]; then
    echo "🧪 Running tests..."
    node test.js
fi

cd ..

echo "🎉 Build complete!"
echo ""
echo "Usage:"
echo "  Server mode: ./start.sh"
echo "  Embedded mode: cd nodejs-bindings && node test.js"