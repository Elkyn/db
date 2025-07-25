#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is required but not installed${NC}"
    echo "Install with: brew install gh"
    exit 1
fi

# Get version from user or use default
VERSION=${1:-"v0.1.0-alpha"}
echo -e "${BLUE}Creating release for version: $VERSION${NC}"

# Check if we have uncommitted changes
if [[ -n $(git status -s) ]]; then
    echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Build server binaries
echo -e "${BLUE}Building server binaries...${NC}"
if [[ -f "./build_docker.sh" ]]; then
    ./build_docker.sh
else
    echo -e "${YELLOW}Docker build script not found, building native only${NC}"
    ./build_native.sh
fi

# Build Node.js binaries
echo -e "${BLUE}Building Node.js binaries...${NC}"
if [[ -f "./build_node_binaries.sh" ]]; then
    ./build_node_binaries.sh
else
    echo -e "${YELLOW}Node.js build script not found${NC}"
fi

# Create release directory
RELEASE_DIR="release-$VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Copy binaries to release directory
echo -e "${BLUE}Preparing release artifacts...${NC}"
cp dist/* "$RELEASE_DIR/" 2>/dev/null || true
cp dist/node/*.node "$RELEASE_DIR/" 2>/dev/null || true

# Create README for the release
cat > "$RELEASE_DIR/README.txt" << EOF
Elkyn DB $VERSION

⚠️ ALPHA SOFTWARE - This is alpha software under active development.
APIs may change and data compatibility is not guaranteed between versions.

Installation:
1. Download the appropriate binary for your platform
2. Make it executable (Linux/macOS): chmod +x elkyn-server-*
3. Run the server: ./elkyn-server-*

Binary Description:
This release includes a native binary for the build platform only.
For other platforms, please build from source or use GitHub Actions.

For static builds or to build from source, see the main README.
EOF

# Create release notes
echo -e "${BLUE}Creating release notes...${NC}"
cat > release_notes.md << EOF
## Elkyn DB $VERSION

⚠️ **ALPHA SOFTWARE** - This is alpha software under active development. APIs may change and data compatibility is not guaranteed between versions.

### What's New
- Initial alpha release
- Tree-structured real-time database
- JWT authentication with declarative security rules
- Server-Sent Events for real-time updates
- Web dashboard for testing

### Installation

Download the appropriate binary for your platform and make it executable:

\`\`\`bash
# Linux/macOS
chmod +x elkyn-server-*
./elkyn-server-*

# Windows
elkyn-server-*.exe
\`\`\`

### System Requirements

These binaries require LMDB to be installed on your system:

- **Linux**: \`sudo apt install lmdb-dev\` or \`yum install lmdb\`
- **macOS**: \`brew install lmdb\`
- **Windows**: Download LMDB binaries and ensure lmdb.dll is in PATH

### Checksums

Verify your download with the provided checksum files in the release.
EOF

# Create the release
echo -e "${BLUE}Creating GitHub release...${NC}"

# Check if tag already exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo -e "${YELLOW}Tag $VERSION already exists${NC}"
    # Check if release already exists
    if gh release view "$VERSION" >/dev/null 2>&1; then
        echo -e "${YELLOW}GitHub release for $VERSION already exists${NC}"
        read -p "Update existing release with new binaries? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Upload new binaries to existing release
            gh release upload "$VERSION" $RELEASE_DIR/* --clobber
            echo -e "${GREEN}✨ Updated release $VERSION with new binaries!${NC}"
        else
            echo -e "${YELLOW}Release update cancelled.${NC}"
        fi
    else
        # Tag exists but no release
        read -p "Create GitHub release for existing tag $VERSION? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gh release create "$VERSION" \
                --title "Elkyn DB $VERSION" \
                --notes-file release_notes.md \
                --prerelease \
                $RELEASE_DIR/*
            echo -e "${GREEN}✨ Release $VERSION created successfully!${NC}"
        fi
    fi
else
    # Tag doesn't exist - create both tag and release
    echo -e "${YELLOW}This will create tag $VERSION and push it to GitHub${NC}"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create and push tag
        git tag -a "$VERSION" -m "Release $VERSION"
        git push origin "$VERSION"
        
        # Create release with gh CLI
        gh release create "$VERSION" \
            --title "Elkyn DB $VERSION" \
            --notes-file release_notes.md \
            --prerelease \
            $RELEASE_DIR/*
        
        echo -e "${GREEN}✨ Release $VERSION created successfully!${NC}"
    else
        echo -e "${YELLOW}Release cancelled. Tag not created.${NC}"
        echo -e "${YELLOW}Binaries are available in: $RELEASE_DIR/${NC}"
    fi
fi

echo -e "${GREEN}View at: https://github.com/Elkyn/db/releases/tag/$VERSION${NC}"

# Cleanup
rm -f release_notes.md