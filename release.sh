#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Elkyn DB Release Process${NC}"
echo ""

# Step 1: Update version
echo -e "${BLUE}Step 1: Update version${NC}"
./update_version.sh

# Get the version that was set
VERSION=$(cat VERSION)
VERSION_WITH_V="v$VERSION"

# Step 2: Commit version changes
echo ""
echo -e "${BLUE}Step 2: Commit version changes${NC}"
read -p "Review changes and commit? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git add -A
    git commit -m "chore: bump version to $VERSION"
    echo -e "${GREEN}✓ Committed version changes${NC}"
else
    echo -e "${YELLOW}Skipping commit${NC}"
fi

# Step 3: Create and push tag
echo ""
echo -e "${BLUE}Step 3: Create git tag${NC}"
read -p "Create and push tag $VERSION_WITH_V? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git tag -a "$VERSION_WITH_V" -m "Release $VERSION_WITH_V"
    git push origin main
    git push origin "$VERSION_WITH_V"
    echo -e "${GREEN}✓ Created and pushed tag${NC}"
else
    echo -e "${RED}Cannot proceed without tag${NC}"
    exit 1
fi

# Step 4: Build and create GitHub release
echo ""
echo -e "${BLUE}Step 4: Build and create GitHub release${NC}"
./create_release.sh "$VERSION_WITH_V"

# Step 5: Publish npm package
echo ""
echo -e "${BLUE}Step 5: Publish npm package${NC}"
echo -e "${YELLOW}The npm package will download binaries from the GitHub release${NC}"
read -p "Publish @elkyn/store@$VERSION to npm? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd nodejs-bindings
    npm publish
    cd ..
    echo -e "${GREEN}✓ Published to npm${NC}"
else
    echo -e "${YELLOW}Skipping npm publish${NC}"
    echo "You can publish later with:"
    echo "  cd nodejs-bindings && npm publish"
fi

echo ""
echo -e "${GREEN}🎉 Release $VERSION_WITH_V complete!${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "  - Version: $VERSION"
echo "  - Git tag: $VERSION_WITH_V"
echo "  - GitHub release: https://github.com/Elkyn/db/releases/tag/$VERSION_WITH_V"
echo "  - NPM package: https://www.npmjs.com/package/@elkyn/store"