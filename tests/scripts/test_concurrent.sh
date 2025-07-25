#!/bin/bash

# Test concurrent performance of Elkyn DB

TOKEN=$(curl -s -X POST http://localhost:8889/auth/token \
  -H "Content-Type: application/json" \
  -d '{"uid": "test-user", "email": "test@example.com"}' | jq -r .token)

echo "Testing with 50 concurrent requests..."
echo "Token: ${TOKEN:0:20}..."

# Function to make a request
make_request() {
  local id=$1
  local start=$(date +%s%N)
  
  curl -s -X PUT "http://localhost:8889/users/test-user/concurrent-$id" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "\"Data item $id\"" > /dev/null
  
  local end=$(date +%s%N)
  local duration=$((($end - $start) / 1000000)) # Convert to milliseconds
  echo "Request $id completed in ${duration}ms"
}

# Export function and token for subshells
export -f make_request
export TOKEN

# Start time
start_time=$(date +%s%N)

# Launch 50 concurrent requests
seq 1 50 | xargs -P 50 -I {} bash -c 'make_request {}'

# End time
end_time=$(date +%s%N)
total_time=$((($end_time - $start_time) / 1000000))

echo ""
echo "All requests completed in ${total_time}ms"
echo "Average time per request: $((total_time / 50))ms"

# Verify a few writes
echo ""
echo "Verifying writes..."
for i in 1 5 10 25 50; do
  value=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8889/users/test-user/concurrent-$i")
  echo "concurrent-$i: $value"
done