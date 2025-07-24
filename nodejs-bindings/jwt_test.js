const { ElkynStore } = require('./index');

console.log('🔐 Testing JWT functionality...');

const store = new ElkynStore('./test-jwt');

console.log('1. Enabling auth...');
const authEnabled = store.enableAuth('test-secret');
console.log('Auth enabled:', authEnabled);

console.log('2. Creating token...');
const token = store.createToken('alice', 'alice@example.com');
console.log('Token created:', token);

console.log('3. Testing without auth (should work)...');
try {
    store.setString('/public/test', 'no auth needed');
    console.log('✅ Set without auth works');
    
    const value = store.getString('/public/test');
    console.log('✅ Get without auth works:', value);
} catch (e) {
    console.log('❌ No auth failed:', e.message);
}

console.log('4. Testing with invalid token (expect failure)...');
try {
    store.setString('/test/path', 'value', 'invalid-token');
    console.log('❌ Invalid token should have failed');
} catch (e) {
    console.log('✅ Invalid token correctly rejected:', e.message);
}

console.log('5. Testing with valid token (should work)...');
try {
    store.setString('/test/path', 'value', token);
    console.log('✅ Valid token accepted');
    
    const value = store.getString('/test/path', token);
    console.log('✅ Get with valid token works:', value);
} catch (e) {
    console.log('❌ Valid token failed:', e.message);
}

store.close();
console.log('✅ JWT test complete');