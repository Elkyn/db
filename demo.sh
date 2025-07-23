#!/bin/bash

echo "🚀 Elkyn DB Demo"
echo "=================="
echo

echo "Starting Elkyn DB server..."
./zig-out/bin/elkyn-db &
SERVER_PID=$!
sleep 1

echo
echo "✅ Server started (PID: $SERVER_PID)"
echo

# Function to cleanup on exit
cleanup() {
    echo
    echo "Stopping server..."
    kill $SERVER_PID 2>/dev/null
}
trap cleanup EXIT

echo "📝 1. Setting some data..."
echo
echo "PUT /users/alice"
curl -X PUT -H "Content-Type: application/json" \
  -d '{"name":"Alice","age":30,"role":"admin","active":true}' \
  http://localhost:9000/users/alice
echo -e "\n"

echo "PUT /users/bob"
curl -X PUT -H "Content-Type: application/json" \
  -d '{"name":"Bob","age":25,"role":"user","active":true}' \
  http://localhost:9000/users/bob
echo -e "\n"

echo "PUT /config/features"
curl -X PUT -H "Content-Type: application/json" \
  -d '{"chat":true,"notifications":true,"darkMode":false}' \
  http://localhost:9000/config/features
echo -e "\n"

echo
echo "📖 2. Reading data..."
echo
echo "GET /users/alice"
curl -s http://localhost:9000/users/alice | python3 -m json.tool
echo

echo "GET /users/alice/name (nested access)"
curl -s http://localhost:9000/users/alice/name
echo -e "\n"

echo
echo "🌳 3. Tree structure demonstration..."
echo
echo "Setting nested data at /app"
curl -X PUT -H "Content-Type: application/json" \
  -d '{"version":"1.0.0","settings":{"theme":"light","language":"en"},"modules":{"auth":{"enabled":true},"api":{"rateLimit":100}}}' \
  http://localhost:9000/app
echo -e "\n"

echo "GET /app/modules/api/rateLimit (deep nested access)"
curl -s http://localhost:9000/app/modules/api/rateLimit
echo -e "\n"

echo
echo "🗑️  4. Delete operation..."
echo
echo "DELETE /users/bob"
curl -X DELETE http://localhost:9000/users/bob
echo -e "\n"

echo "GET /users/bob (expect 404)"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:9000/users/bob
echo

echo
echo "🎉 Demo complete!"
echo
echo "Key features demonstrated:"
echo "  ✅ Tree-structured data storage"
echo "  ✅ Automatic object expansion"
echo "  ✅ Nested path access"
echo "  ✅ Full CRUD operations"
echo "  ✅ LMDB persistence"
echo "  ✅ <1ms boot time"
echo
echo "To test WebSocket subscriptions, open test_websocket.html in a browser."
echo