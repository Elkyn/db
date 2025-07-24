const { ElkynStore } = require('./index');

console.log('🌳 Elkyn Store Demo - Embedded Real-time Database');
console.log('='.repeat(50));

// Initialize database
console.log('\n📁 Initializing database...');
const store = new ElkynStore('./demo-data');
console.log('✅ Database initialized');

// Basic operations
console.log('\n📝 Basic Operations:');
console.log('Setting user data...');
store.set('/users/alice', {
    name: 'Alice Smith',
    email: 'alice@example.com',
    age: 30,
    settings: {
        theme: 'dark',
        notifications: true
    }
});

store.set('/users/bob', {
    name: 'Bob Johnson', 
    email: 'bob@example.com',
    age: 25
});

console.log('✅ User data stored');

// Reading data
console.log('\n📖 Reading data:');
const alice = store.get('/users/alice');
const bobName = store.getString('/users/bob/name');

console.log('Alice:', alice);
console.log('Bob name:', bobName);

// Tree operations
console.log('\n🌲 Tree Operations:');
store.set('/products/laptop', {
    name: 'MacBook Pro',
    price: 2499,
    category: 'electronics'
});

store.set('/products/book', {
    name: 'JavaScript Guide',
    price: 29.99,
    category: 'books'
});

const laptop = store.get('/products/laptop');
console.log('Laptop:', laptop);

// String operations (more efficient)
console.log('\n⚡ String Operations:');
store.setString('/config/app_name', 'My Awesome App');
store.setString('/config/version', '1.0.0');

const appName = store.getString('/config/app_name');
const version = store.getString('/config/version');
console.log(`${appName} v${version}`);

// Delete operations
console.log('\n🗑️ Delete Operations:');
store.delete('/users/bob');
const deletedBob = store.get('/users/bob');
console.log('Bob after deletion:', deletedBob); // Should be null

// Performance test
console.log('\n🚀 Performance Test:');
const start = Date.now();
for (let i = 0; i < 1000; i++) {
    store.setString(`/perf/item_${i}`, `Item number ${i}`);
}
const elapsed = Date.now() - start;
console.log(`✅ 1000 writes completed in ${elapsed}ms (${(1000/elapsed*1000).toFixed(0)} ops/sec)`);

// Read performance
const readStart = Date.now();
for (let i = 0; i < 1000; i++) {
    store.getString(`/perf/item_${i}`);
}
const readElapsed = Date.now() - readStart;
console.log(`✅ 1000 reads completed in ${readElapsed}ms (${(1000/readElapsed*1000).toFixed(0)} ops/sec)`);

// Cleanup
console.log('\n🧹 Cleanup:');
store.close();
console.log('✅ Database closed');

console.log('\n🎉 Demo complete! Key features:');
console.log('  ✅ Tree-structured data storage');
console.log('  ✅ JSON and string operations');
console.log('  ✅ High performance (native Zig core)');
console.log('  ✅ ACID compliant (LMDB backend)');
console.log('  ✅ Easy Node.js integration');
console.log('\n🔜 Coming soon: JWT auth, security rules, real-time events');