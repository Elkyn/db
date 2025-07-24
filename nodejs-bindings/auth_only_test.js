const { ElkynStore } = require('./index');

console.log('🔐 Testing auth without rules...');

const store = new ElkynStore('./test-auth-only');

console.log('1. Setting data without auth...');
store.setString('/test', 'before auth');
console.log('✅ Works without auth');

console.log('2. Enabling auth...');
store.enableAuth('test-secret');

console.log('3. Setting data after auth enabled (no rules)...');
try {
    const token = store.createToken('alice');
    console.log('Token:', token.slice(0, 50) + '...');
    
    // Try direct C binding first
    const binding = require('./build/Release/elkyn_store');
    const result = binding.setString(store.handle, '/test2', 'with token', token);
    console.log('Direct binding result:', result);
    
} catch (e) {
    console.log('❌ Failed:', e.message);
}

store.close();