#!/bin/bash

echo "=== Real-Time Update Test ==="
echo

# Clean up first
curl -s -X DELETE http://localhost:8889/test/value
curl -s -X DELETE http://localhost:8889/test/counter

echo "Starting SSE connections..."
echo "Connection 1 watching /test/value:"
curl -N http://localhost:8889/test/value/.watch 2>/dev/null | while IFS= read -r line; do
    echo "[SSE-1] $line"
done &
PID1=$!

echo "Connection 2 watching /test/counter:"
curl -N http://localhost:8889/test/counter/.watch 2>/dev/null | while IFS= read -r line; do
    echo "[SSE-2] $line"
done &
PID2=$!

# Wait for connections
sleep 2

echo
echo "--- Test 1: Setting initial values ---"
./test_client  # Sets /test/value to "Hello SSE!"
sleep 1

# Set counter
cat > set_counter.zig << 'EOF'
const std = @import("std");
pub fn main() !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 8889);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();
    
    const request = 
        "PUT /test/counter HTTP/1.1\r\n" ++
        "Host: localhost:8889\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 1\r\n" ++
        "\r\n" ++
        "0";
    
    _ = try stream.write(request);
    var buffer: [1024]u8 = undefined;
    const bytes_read = try stream.read(&buffer);
    std.debug.print("Set counter response: OK\n", .{});
}
EOF
zig build-exe set_counter.zig 2>/dev/null && ./set_counter

sleep 2

echo
echo "--- Test 2: Updating values ---"
# Update value
cat > update_value.zig << 'EOF'
const std = @import("std");
pub fn main() !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 8889);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();
    
    const request = 
        "PUT /test/value HTTP/1.1\r\n" ++
        "Host: localhost:8889\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 26\r\n" ++
        "\r\n" ++
        "\"Real-time updates work!\"";
    
    _ = try stream.write(request);
    var buffer: [1024]u8 = undefined;
    const bytes_read = try stream.read(&buffer);
    std.debug.print("Update value: OK\n", .{});
}
EOF
zig build-exe update_value.zig 2>/dev/null && ./update_value

# Update counter
cat > update_counter.zig << 'EOF'
const std = @import("std");
pub fn main() !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 8889);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();
    
    const request = 
        "PUT /test/counter HTTP/1.1\r\n" ++
        "Host: localhost:8889\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 2\r\n" ++
        "\r\n" ++
        "42";
    
    _ = try stream.write(request);
    var buffer: [1024]u8 = undefined;
    const bytes_read = try stream.read(&buffer);
    std.debug.print("Update counter: OK\n", .{});
}
EOF
zig build-exe update_counter.zig 2>/dev/null && ./update_counter

sleep 2

echo
echo "--- Test 3: Deleting values ---"
curl -s -X DELETE http://localhost:8889/test/value
echo "Delete value: OK"
curl -s -X DELETE http://localhost:8889/test/counter
echo "Delete counter: OK"

sleep 2

echo
echo "Stopping SSE connections..."
kill $PID1 $PID2 2>/dev/null

echo "Test complete!"
rm -f set_counter update_value update_counter test_update