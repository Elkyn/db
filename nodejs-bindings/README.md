# @elkyn/store

Embedded real-time tree database with Firebase-style security rules for Node.js.

## Features

- 🌳 **Tree-structured data** - Intuitive path-based organization
- ⚡ **Zero-copy operations** - Built with Zig for maximum performance
- 🔒 **JWT authentication** - Secure token-based access control
- 🛡️ **Security rules** - Firebase-compatible declarative rules
- 💾 **LMDB storage** - ACID compliant, crash-safe persistence
- 🔗 **Native bindings** - Direct C interface, no overhead

## Installation

```bash
npm install @elkyn/store
```

**Prerequisites:**
- Node.js 16+
- LMDB system library (`brew install lmdb` on macOS)
- C++ compiler for native compilation

## Quick Start

```javascript
const { ElkynStore } = require('@elkyn/store');

// Initialize database
const store = new ElkynStore('./my-data');

// Basic operations
store.set('/users/123', {
    name: 'Alice',
    email: 'alice@example.com'
});

const user = store.get('/users/123');
console.log(user); // { name: 'Alice', email: 'alice@example.com' }

// Clean up
store.close();
```

## Authentication & Security

```javascript
// Enable JWT authentication
store.enableAuth('your-secret-key');

// Setup Firebase-style security rules
store.setupDefaultRules();
// Or custom rules:
store.enableRules({
    rules: {
        users: {
            "$userId": {
                ".read": "$userId === auth.uid",
                ".write": "$userId === auth.uid"
            }
        }
    }
});

// Create tokens and access data
const token = store.createToken('alice', 'alice@example.com');

// Secure operations
store.set('/users/alice/private', { secret: 'data' }, token);
const private = store.get('/users/alice/private', token);
```

## API Reference

### Constructor

#### `new ElkynStore(dataDir)`
- `dataDir` (string): Directory path for database files

### Authentication

#### `enableAuth(secret: string): boolean`
Enable JWT authentication with the given secret key.

#### `createToken(uid: string, email?: string): string`
Create a JWT token for testing/development. Throws if auth not enabled.

### Security Rules

#### `enableRules(rules: string | object): boolean`
Load Firebase-style security rules from JSON string or object.

#### `setupDefaultRules(): boolean`
Enable default rules: users can only access their own data.

### Data Operations

#### `set(path: string, value: any, token?: string): boolean`
Set JSON value at path. Throws on auth/rules violation.

#### `get(path: string, token?: string): any`
Get and parse JSON value. Returns null if not found. Throws on access denied.

#### `setString(path: string, value: string, token?: string): boolean`
Set raw string value. More efficient than JSON operations.

#### `getString(path: string, token?: string): string | null`
Get raw string value.

#### `delete(path: string, token?: string): boolean`
Delete value at path. Throws on auth/rules violation.

### Lifecycle

#### `close(): void`
Close database connection and free resources.

## Security Rules Syntax

Rules follow Firebase Realtime Database syntax:

```javascript
{
    "rules": {
        // Public read access
        "public": {
            ".read": "true",
            ".write": "false"
        },
        
        // User-specific data
        "users": {
            "$userId": {
                ".read": "$userId === auth.uid",
                ".write": "$userId === auth.uid",
                
                // Public profile info
                "name": {
                    ".read": "true"
                }
            }
        },
        
        // Admin-only data
        "admin": {
            ".read": "auth.uid === 'admin'",
            ".write": "auth.uid === 'admin'"
        }
    }
}
```

### Rule Variables

- `auth.uid` - User ID from JWT token
- `auth.email` - Email from JWT token
- `$variable` - Path variables (e.g., `$userId`)
- `true/false` - Literal boolean values

## Error Handling

```javascript
try {
    store.set('/protected/data', { value: 123 }, invalidToken);
} catch (error) {
    if (error.message === 'Authentication failed') {
        // Invalid or expired token
    } else if (error.message === 'Access denied') {
        // Rules prevented access
    }
}
```

## Performance

- **Zero-copy reads** - Direct access to LMDB data
- **Batch operations** - Multiple operations in single transaction
- **Memory efficient** - No JSON parsing for string operations
- **Native speed** - Zig-compiled core with C bindings

## License

MIT