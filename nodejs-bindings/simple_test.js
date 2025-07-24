const { ElkynStore } = require('./index');

console.log('Creating store...');
const store = new ElkynStore('./test-simple');

console.log('Setting string...');
try {
    store.setString('/test', 'hello world');
    console.log('✅ Set string successful');
} catch (e) {
    console.log('❌ Set failed:', e.message);
}

console.log('Getting string...');
try {
    const result = store.getString('/test');
    console.log('✅ Got string:', result);
} catch (e) {
    console.log('❌ Get failed:', e.message);
}

console.log('Closing store...');
store.close();
console.log('✅ Test complete');