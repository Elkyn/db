#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Running Elkyn DB Tests${NC}"
echo ""

# Run unit tests
echo -e "${BLUE}Running unit tests...${NC}"
if zig build test; then
    echo -e "${GREEN}✓ Unit tests passed${NC}"
else
    echo -e "${RED}✗ Unit tests failed${NC}"
    exit 1
fi

# Run integration tests (if requested)
if [[ "$1" == "--integration" ]]; then
    echo ""
    echo -e "${BLUE}Running integration tests...${NC}"
    echo -e "${BLUE}Available test scripts:${NC}"
    ls tests/scripts/*.sh | sed 's/.*\//  - /'
    echo ""
    echo "Run individual tests with: ./tests/scripts/<test_name>.sh"
fi

echo ""
echo -e "${GREEN}✨ Tests complete!${NC}"