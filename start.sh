#!/bin/bash

# Elkyn DB Quick Start Script

echo "🚀 Starting Elkyn DB..."
echo ""

# Default values
PORT="${1:-8889}"
DATA_DIR="${2:-./data}"
SECRET="${3:-test-secret}"
THREADS="${4:-8}"

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

echo "Configuration:"
echo "  Port: $PORT"
echo "  Data: $DATA_DIR"
echo "  Threads: $THREADS"
echo "  Auth: Enabled"
echo ""
echo "Dashboard: http://localhost:$PORT/index.html"
echo ""

# Launch with all features enabled for testing
./zig-out/bin/elkyn-server "$PORT" "$DATA_DIR" "$SECRET" \
  --allow-token-generation \
  --threads="$THREADS"