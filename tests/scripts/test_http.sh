#!/bin/bash

echo "Testing Elkyn DB HTTP API..."
echo

# Test PUT
echo "1. PUT /test/message"
curl -X PUT -H "Content-Type: application/json" -d '"Hello, Elkyn!"' http://localhost:9000/test/message
echo -e "\n"

# Test GET
echo "2. GET /test/message"
curl http://localhost:9000/test/message
echo -e "\n"

# Test PUT object
echo "3. PUT /users/alice (object)"
curl -X PUT -H "Content-Type: application/json" -d '{"name":"Alice","age":30,"active":true}' http://localhost:9000/users/alice
echo -e "\n"

# Test GET object
echo "4. GET /users/alice"
curl http://localhost:9000/users/alice
echo -e "\n"

# Test GET nested
echo "5. GET /users/alice/name"
curl http://localhost:9000/users/alice/name
echo -e "\n"

# Test 404
echo "6. GET /not/found (expect 404)"
curl -i http://localhost:9000/not/found | head -n 1
echo -e "\n"

# Test PATCH
echo "7. PATCH /users/alice (partial update)"
curl -X PATCH -H "Content-Type: application/json" -d '{"age":31,"city":"New York"}' http://localhost:9000/users/alice
echo -e "\n"

# Verify PATCH
echo "8. GET /users/alice (after PATCH)"
curl http://localhost:9000/users/alice
echo -e "\n"

# Test DELETE
echo "9. DELETE /test/message"
curl -X DELETE http://localhost:9000/test/message
echo -e "\n"

# Verify DELETE
echo "10. GET /test/message (expect 404)"
curl -i http://localhost:9000/test/message | head -n 1
echo -e "\n"

echo "Tests complete!"