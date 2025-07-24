#!/bin/bash

# Quick development server launcher

echo "🚀 Starting Elkyn DB in development mode..."
echo ""

# Kill any existing servers on port 8889
pkill -f "elkyn-server.*8889" 2>/dev/null && echo "Stopped existing server"

# Build if needed
if [ ! -f "./zig-out/bin/elkyn-server" ] || [ "$1" == "--build" ]; then
    echo "Building..."
    zig build -Doptimize=Debug
fi

# Start server with auth enabled
echo "Starting server on port 8889 with authentication..."
./launch.sh 8889 ./dev-data test-secret

# When server exits, show dashboard URL
echo ""
echo "Server stopped. To access the dashboard, visit:"
echo "http://localhost:8889/index.html"