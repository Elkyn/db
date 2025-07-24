#!/bin/bash

# Start watching /test/value in the background
echo "Starting SSE connection..."
curl -N http://localhost:8889/test/value/.watch &
SSE_PID=$!

# Give it a second to connect
sleep 1

# Update the value
echo -e "\nUpdating value to 'Hello from realtime'..."
curl -X PUT http://localhost:8889/test/value -H "Content-Type: application/json" -d '"Hello from realtime"'

# Wait a bit to see the update
sleep 2

# Update again
echo -e "\nUpdating value to 'Second update'..."
curl -X PUT http://localhost:8889/test/value -H "Content-Type: application/json" -d '"Second update"'

# Wait a bit more
sleep 2

# Delete the value
echo -e "\nDeleting value..."
curl -X DELETE http://localhost:8889/test/value

# Wait to see the delete
sleep 2

# Kill the SSE connection
kill $SSE_PID 2>/dev/null

echo -e "\nTest complete!"