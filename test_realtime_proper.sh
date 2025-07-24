#!/bin/bash

echo "=== Testing Real-Time Updates ==="
echo

# Start SSE connection in background
echo "1. Starting SSE connection..."
curl -N http://localhost:8889/test/value/.watch 2>/dev/null &
SSE_PID=$!

# Wait for connection
sleep 1

echo
echo "2. Setting value using raw HTTP..."
./test_client

# Wait to see update
sleep 2

echo
echo "3. Checking stored value..."
curl -s http://localhost:8889/test/value

echo
echo
echo "4. Updating value again..."
# Create another test client for update
cat > test_update.zig << 'EOF'
const std = @import("std");

pub fn main() !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 8889);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();
    
    const request = 
        "PUT /test/value HTTP/1.1\r\n" ++
        "Host: localhost:8889\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 17\r\n" ++
        "\r\n" ++
        "\"Real-time works!\"";
    
    _ = try stream.write(request);
    
    var buffer: [1024]u8 = undefined;
    const bytes_read = try stream.read(&buffer);
    std.debug.print("Update response: {s}\n", .{buffer[0..bytes_read]});
}
EOF

zig build-exe test_update.zig 2>/dev/null && ./test_update

# Wait for update
sleep 2

echo
echo "5. Stopping SSE connection..."
kill $SSE_PID 2>/dev/null

echo "Test complete!"