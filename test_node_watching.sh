#!/bin/bash

echo "=== Testing Node Watching ==="
echo

# Clean up
curl -s -X DELETE http://localhost:8889/products
curl -s -X DELETE http://localhost:8889/users

echo "1. Setting up initial data..."
# Create some data
curl -s -X PUT http://localhost:8889/products/laptop -H "Content-Type: application/json" -d '{"name":"Laptop","price":999}'
curl -s -X PUT http://localhost:8889/products/phone -H "Content-Type: application/json" -d '{"name":"Phone","price":599}'
curl -s -X PUT http://localhost:8889/users/alice -H "Content-Type: application/json" -d '{"name":"Alice","role":"admin"}'
curl -s -X PUT http://localhost:8889/users/bob -H "Content-Type: application/json" -d '{"name":"Bob","role":"user"}'

echo "✓ Initial data created"
echo

echo "2. Starting watchers on different paths..."
echo "   - Watcher 1: Watching /products (should see product updates)"
echo "   - Watcher 2: Watching /users (should see user updates)"
echo "   - Watcher 3: Watching / (should see all updates)"
echo

# Start watchers
curl -N http://localhost:8889/products/.watch 2>/dev/null | while read line; do echo "[/products] $line"; done &
PID1=$!

curl -N http://localhost:8889/users/.watch 2>/dev/null | while read line; do echo "[/users] $line"; done &
PID2=$!

curl -N http://localhost:8889/.watch 2>/dev/null | while read line; do echo "[/] $line"; done &
PID3=$!

# Give watchers time to connect
sleep 2

echo
echo "3. Updating product..."
curl -s -X PUT http://localhost:8889/products/laptop -H "Content-Type: application/json" -d '{"name":"Gaming Laptop","price":1299}'
echo "✓ Updated /products/laptop"

sleep 2

echo
echo "4. Adding new user..."
curl -s -X PUT http://localhost:8889/users/charlie -H "Content-Type: application/json" -d '{"name":"Charlie","role":"moderator"}'
echo "✓ Created /users/charlie"

sleep 2

echo
echo "5. Updating nested path..."
curl -s -X PUT http://localhost:8889/products/laptop/reviews -H "Content-Type: application/json" -d '[{"rating":5,"comment":"Great!"}]'
echo "✓ Created /products/laptop/reviews"

sleep 2

echo
echo "6. Deleting a product..."
curl -s -X DELETE http://localhost:8889/products/phone
echo "✓ Deleted /products/phone"

sleep 2

echo
echo "Stopping watchers..."
kill $PID1 $PID2 $PID3 2>/dev/null

echo
echo "Test complete!"