#!/bin/bash

# Test authentication with Elkyn DB

echo "Starting server with auth enabled and token generation allowed (for testing)..."
./zig-out/bin/elkyn-server 9001 ./test-data test-secret require --allow-token-generation &
SERVER_PID=$!
sleep 2

echo -e "\n1. Testing unauthenticated request (should fail):"
curl -i http://localhost:9001/test 2>/dev/null | head -1

echo -e "\n2. Getting auth token:"
TOKEN_RESPONSE=$(curl -s -X POST http://localhost:9001/auth/token \
  -H "Content-Type: application/json" \
  -d '{"uid": "test-user", "email": "test@example.com"}')

TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['token'])" 2>/dev/null || echo "")
echo "Token: ${TOKEN:0:50}..."

echo -e "\n3. Testing authenticated request:"
curl -i -H "Authorization: Bearer $TOKEN" \
  -X PUT http://localhost:9001/test \
  -H "Content-Type: application/json" \
  -d '"Hello from authenticated user!"' 2>/dev/null | head -1

echo -e "\n4. Reading back with auth:"
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:9001/test

echo -e "\n\nCleaning up..."
kill $SERVER_PID
rm -rf ./test-data