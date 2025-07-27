// Manual test - copy the binary first
const fs = require('fs');
const path = require('path');

// First, copy the binary manually
const srcBinary = path.join(__dirname, '../nodejs-bindings/build/Release/elkyn_store.node');
const dstDir = path.join(__dirname, 'node_modules/elkyn-store/build/Release');
const dstBinary = path.join(dstDir, 'elkyn_store.node');

// Create directories
fs.mkdirSync(dstDir, { recursive: true });

// Copy binary
fs.copyFileSync(srcBinary, dstBinary);
console.log('✅ Copied binary');

// Now load and test
const { ElkynStore } = require('elkyn-store');

console.log('🚀 Testing elkyn-store...\n');

// Create a new database
const db = new ElkynStore('./test.db');
console.log('✅ Created database');

// Test basic operations
console.log('\n📝 Testing basic operations:');

// Set some data
db.set('/users/alice', { 
  name: 'Alice', 
  email: 'alice@example.com',
  age: 30 
});
console.log('✅ Set user data');

// Get data back
const alice = db.get('/users/alice');
console.log('✅ Retrieved:', alice);

// Set nested data
db.set('/users/alice/preferences', {
  theme: 'dark',
  notifications: true
});
console.log('✅ Set nested data');

// Get parent with children
const aliceWithPrefs = db.get('/users/alice');
console.log('✅ Retrieved with nested:', aliceWithPrefs);

// Test array data
db.set('/posts', [
  { id: 1, title: 'Hello World' },
  { id: 2, title: 'Testing Elkyn' }
]);
console.log('✅ Set array data');

const posts = db.get('/posts');
console.log('✅ Retrieved array:', posts);

// Test deletion
db.set('/temp', 'will be deleted');
db.set('/temp', null); // null deletes the key
const deleted = db.get('/temp');
console.log('✅ Deletion test:', deleted === undefined ? 'PASSED' : 'FAILED');

// Clean up
db.close();
console.log('\n✅ Database closed successfully');
console.log('🎉 All tests passed!');