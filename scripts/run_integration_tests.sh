#!/bin/bash

set -e

echo "Building server..."
zig build

# Create temp directory for test data
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "Starting server on port 8888 with data dir: $TEST_DIR"
./zig-out/bin/elkyn-server 8888 "$TEST_DIR" &
SERVER_PID=$!

# Function to kill server on exit
cleanup() {
    echo "Stopping server..."
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for server to start
sleep 2

echo "Running integration tests..."

# Test 1: Basic GET (should 404 initially)
echo "Test 1: GET non-existent key"
RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:8888/test/key)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" != "404" ]; then
    echo "FAIL: Expected 404, got $HTTP_CODE"
    exit 1
fi
echo "PASS: Got 404 for non-existent key"

# Test 2: PUT a value
echo "Test 2: PUT a value"
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d '"test value"' http://localhost:8888/test/key)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" != "200" ]; then
    echo "FAIL: Expected 200, got $HTTP_CODE"
    exit 1
fi
echo "PASS: PUT successful"

# Test 3: GET the value back
echo "Test 3: GET the value"
RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:8888/test/key)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
if [ "$HTTP_CODE" != "200" ]; then
    echo "FAIL: Expected 200, got $HTTP_CODE"
    exit 1
fi
if [ "$BODY" != '"test value"' ]; then
    echo "FAIL: Expected '\"test value\"', got '$BODY'"
    exit 1
fi
echo "PASS: GET returned correct value"

# Test 4: DELETE the value
echo "Test 4: DELETE the value"
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE http://localhost:8888/test/key)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" != "200" ]; then
    echo "FAIL: Expected 200, got $HTTP_CODE"
    exit 1
fi
echo "PASS: DELETE successful"

# Test 5: GET should 404 again
echo "Test 5: GET after DELETE"
RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:8888/test/key)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" != "404" ]; then
    echo "FAIL: Expected 404, got $HTTP_CODE"
    exit 1
fi
echo "PASS: Got 404 after DELETE"

echo "All integration tests passed!"