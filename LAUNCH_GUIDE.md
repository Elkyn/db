# Elkyn DB Server Launch Guide

## Building the Server

First, ensure you have Zig installed (version 0.14.0 or later) and LMDB development libraries:

```bash
# macOS
brew install zig lmdb

# Ubuntu/Debian
apt install zig liblmdb-dev

# Build the project
zig build -Doptimize=ReleaseFast
```

After building, the executables will be in `zig-out/bin/`:
- `elkyn-server` - The main server with auth and rules support
- `elkyn-db` - Basic server without auth (legacy)

## Launch Options

### 1. Basic Server (No Authentication)

```bash
# Default port 8080, data in ./data
./zig-out/bin/elkyn-server

# Custom port and data directory
./zig-out/bin/elkyn-server 9000 /path/to/data
```

### 2. Server with Authentication

```bash
# Enable JWT authentication with a secret key
./zig-out/bin/elkyn-server 9000 ./data your-secret-key

# With required authentication (all endpoints except /auth/token require auth)
./zig-out/bin/elkyn-server 9000 ./data your-secret-key require
```

When authentication is enabled:
- JWT tokens can be generated at `/auth/token`
- Security rules are automatically enabled
- Default rules protect user data and admin paths

### 3. Production Setup

```bash
# Create a startup script
cat > start-elkyn.sh << 'EOF'
#!/bin/bash
DATA_DIR="/var/lib/elkyn-db"
PORT=8080
SECRET_KEY=$(openssl rand -base64 32)

# Ensure data directory exists
mkdir -p $DATA_DIR

# Start server with authentication required
./zig-out/bin/elkyn-server $PORT $DATA_DIR "$SECRET_KEY" require
EOF

chmod +x start-elkyn.sh
./start-elkyn.sh
```

## Testing the Server

### 1. Check if server is running

```bash
curl http://localhost:8080/
```

### 2. Access the Web Dashboard

Open in your browser:
```
http://localhost:8080/index.html
```

### 3. Test with Authentication

```bash
# Get a token
TOKEN=$(curl -s -X POST http://localhost:8080/auth/token \
  -H "Content-Type: application/json" \
  -d '{"uid": "test-user", "email": "test@example.com"}' \
  | jq -r .token)

# Use the token
curl -H "Authorization: Bearer $TOKEN" \
  -X PUT http://localhost:8080/users/test-user \
  -H "Content-Type: application/json" \
  -d '{"name": "Test User"}'
```

## Default Security Rules

When authentication is enabled, these rules are applied:

```javascript
{
  "rules": {
    "users": {
      "$userId": {
        ".read": "$userId === auth.uid",   // Users can only read their own data
        ".write": "$userId === auth.uid",  // Users can only write their own data
        "name": {
          ".read": "true"                  // Anyone can read user names
        },
        "email": {
          ".read": "$userId === auth.uid"  // Only user can read their email
        }
      }
    },
    "public": {
      ".read": "true",                     // Anyone can read public data
      ".write": "auth != null"             // Only authenticated users can write
    },
    "admin": {
      ".read": "false",                    // No one can read admin data
      ".write": "false"                    // No one can write admin data
    }
  }
}
```

## Common Issues

### Port Already in Use
```bash
# Find process using port 8080
lsof -i :8080

# Kill the process
kill -9 <PID>
```

### Permission Denied
```bash
# Ensure data directory is writable
chmod -R 755 ./data
```

### Server Crashes on Startup
```bash
# Check if LMDB is installed
ldconfig -p | grep lmdb

# Run with debug output
RUST_LOG=debug ./zig-out/bin/elkyn-server
```

## Development Mode

For development with auto-reload:

```bash
# Terminal 1: Watch for changes and rebuild
while true; do
  inotifywait -r -e modify src/
  zig build
done

# Terminal 2: Run server
./zig-out/bin/elkyn-server 8080 ./data test-secret
```

## Docker Deployment (Coming Soon)

```bash
# Build Docker image
docker build -t elkyn-db .

# Run container
docker run -p 8080:8080 -v $(pwd)/data:/data elkyn-db
```

## Environment Variables

You can also configure the server using environment variables:

```bash
export ELKYN_PORT=8080
export ELKYN_DATA_DIR=/var/lib/elkyn-db
export ELKYN_AUTH_SECRET=your-secret-key
export ELKYN_REQUIRE_AUTH=true

./zig-out/bin/elkyn-server
```

Note: Command-line arguments take precedence over environment variables.