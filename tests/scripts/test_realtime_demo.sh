#!/bin/bash

echo "=== Elkyn DB Real-Time Demo ==="
echo

# Clean slate
echo "1. Deleting any existing value at /test/value..."
curl -s -X DELETE http://localhost:8889/test/value
echo

# Start 3 SSE connections in the background
echo "2. Starting 3 SSE connections to watch /test/value..."
echo "   Connection 1:"
curl -N http://localhost:8889/test/value/.watch 2>/dev/null | sed 's/^/     [SSE-1] /' &
PID1=$!

echo "   Connection 2:"
curl -N http://localhost:8889/test/value/.watch 2>/dev/null | sed 's/^/     [SSE-2] /' &
PID2=$!

echo "   Connection 3:"
curl -N http://localhost:8889/test/value/.watch 2>/dev/null | sed 's/^/     [SSE-3] /' &
PID3=$!

# Give them time to connect
sleep 2

echo
echo "3. Setting initial value..."
curl -s -X PUT http://localhost:8889/test/value -H "Content-Type: application/json" -d '"Initial value"'
echo " ✓ Done"

sleep 2

echo
echo "4. Updating value..."
curl -s -X PUT http://localhost:8889/test/value -H "Content-Type: application/json" -d '"Updated value!"'
echo " ✓ Done"

sleep 2

echo
echo "5. Deleting value..."
curl -s -X DELETE http://localhost:8889/test/value
echo " ✓ Done"

sleep 2

echo
echo "6. Stopping SSE connections..."
kill $PID1 $PID2 $PID3 2>/dev/null
echo " ✓ Done"

echo
echo "Demo complete!"