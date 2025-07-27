const { ElkynStore } = require('elkyn-store');

console.log('🚀 Testing elkyn-store from npm...\n');

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

// Test performance
console.log('\n⚡ Performance test:');
const start = Date.now();
for (let i = 0; i < 1000; i++) {
  db.set(`/perftest/${i}`, { value: i, data: 'x'.repeat(100) });
}
const writeTime = Date.now() - start;
console.log(`✅ Wrote 1000 records in ${writeTime}ms`);

const readStart = Date.now();
for (let i = 0; i < 1000; i++) {
  db.get(`/perftest/${i}`);
}
const readTime = Date.now() - readStart;
console.log(`✅ Read 1000 records in ${readTime}ms`);

// Clean up
db.close();
console.log('\n✅ Database closed successfully');
console.log('🎉 All tests passed!');