#!/bin/bash

# Simple test for thread pool server

echo "Starting thread pool server..."
./zig-out/bin/elkyn-server 8080 test_data test_secret optional --allow-token-generation --threads=2 &
SERVER_PID=$!

# Give server time to fully start
sleep 3

echo "Testing if server is responsive..."
# Simple PUT
curl -v -X PUT http://localhost:8080/test/value \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from thread pool server"}'

echo -e "\n\nGetting the value back..."
# Simple GET
curl -v -X GET http://localhost:8080/test/value

echo -e "\n\nGetting auth token..."
# Get auth token
curl -v -X POST http://localhost:8080/auth/token \
  -H "Content-Type: application/json" \
  -d '{"uid": "test_user", "email": "test@example.com"}'

# Kill server
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

echo -e "\n\nTest complete"