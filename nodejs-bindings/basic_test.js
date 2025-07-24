// Test the C bindings directly
const binding = require('./build/Release/elkyn_store');

console.log('Testing C bindings directly...');

console.log('1. Initializing database...');
const handle = binding.init('./test-basic');
if (!handle) {
    console.log('❌ Failed to initialize');
    process.exit(1);
}
console.log('✅ Database initialized, handle:', handle);

console.log('2. Setting string...');
const setResult = binding.setString(handle, '/test', 'hello world');
console.log('✅ Set result:', setResult);

console.log('3. Getting string...');
const getValue = binding.getString(handle, '/test');
console.log('✅ Get result:', getValue);

console.log('4. Closing...');
binding.close(handle);
console.log('✅ Test complete');