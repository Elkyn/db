#!/bin/bash

# Elkyn DB Launcher Script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PORT=8080
DEFAULT_DATA_DIR="./data"
DEFAULT_SECRET="development-secret-change-in-production"

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if binary exists
if [ ! -f "./zig-out/bin/elkyn-server" ]; then
    print_error "elkyn-server binary not found!"
    print_info "Building the project..."
    zig build -Doptimize=ReleaseFast
    if [ $? -ne 0 ]; then
        print_error "Build failed!"
        exit 1
    fi
fi

# Parse command line arguments
PORT=${1:-$DEFAULT_PORT}
DATA_DIR=${2:-$DEFAULT_DATA_DIR}
AUTH_SECRET=${3:-""}
REQUIRE_AUTH=${4:-""}

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Print configuration
echo "========================================"
echo "       Elkyn DB Server Launcher"
echo "========================================"
print_info "Port: $PORT"
print_info "Data Directory: $DATA_DIR"

if [ -n "$AUTH_SECRET" ]; then
    print_info "Authentication: ENABLED"
    if [ "$AUTH_SECRET" == "$DEFAULT_SECRET" ]; then
        print_warning "Using default secret key - change this in production!"
    fi
    if [ "$REQUIRE_AUTH" == "require" ]; then
        print_info "Auth Required: YES (all endpoints protected)"
    else
        print_info "Auth Required: NO (only some endpoints protected)"
    fi
else
    print_info "Authentication: DISABLED"
    print_warning "Running without authentication - not recommended for production!"
fi

echo "========================================"

# Launch the server
print_info "Starting server..."
if [ -n "$AUTH_SECRET" ]; then
    ./zig-out/bin/elkyn-server "$PORT" "$DATA_DIR" "$AUTH_SECRET" $REQUIRE_AUTH
else
    ./zig-out/bin/elkyn-server "$PORT" "$DATA_DIR"
fi