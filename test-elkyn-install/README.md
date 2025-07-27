# Test Elkyn Store Installation

This is a test project to verify that the `elkyn-store` npm package installs and works correctly.

## Setup

```bash
npm install
```

## Run Test

```bash
npm start
```

## What it tests

1. ✅ Package installation from npm
2. ✅ Binary download from GitHub release
3. ✅ Basic CRUD operations
4. ✅ Nested data structures
5. ✅ Array handling
6. ✅ Deletion
7. ✅ Performance (1000 writes/reads)

## Expected output

The script should:
- Successfully download the correct binary for your platform
- Create a test database
- Perform various operations
- Show performance metrics
- Close cleanly