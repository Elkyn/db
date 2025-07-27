const fs = require('fs');
const path = require('path');

console.log('🐳 Testing elkyn-store in Docker Linux container...\n');

// Check if binary exists
const binaryPath = path.join(__dirname, 'node_modules/elkyn-store/build/Release/elkyn_store.node');
if (!fs.existsSync(binaryPath)) {
  console.error('❌ Binary not found at:', binaryPath);
  console.error('Please ensure the binary is mounted or copied');
  process.exit(1);
}

// Load the module
const { ElkynStore } = require('elkyn-store');

console.log('✅ Module loaded successfully');

// Create a new database
const db = new ElkynStore('./test-docker.db');
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
console.log('🎉 All tests passed in Docker Linux container!');