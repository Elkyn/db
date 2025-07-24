const { ElkynStore } = require('./index');
const path = require('path');
const fs = require('fs');

async function runTests() {
    console.log('🧪 Testing @elkyn/store...\n');
    
    // Create test data directory
    const testDataDir = path.join(__dirname, 'test-data');
    if (fs.existsSync(testDataDir)) {
        fs.rmSync(testDataDir, { recursive: true });
    }
    
    const store = new ElkynStore(testDataDir);
    
    try {
        // Test 1: Basic operations without auth
        console.log('Test 1: Basic operations...');
        console.log('Setting data...');
        store.set('/users/alice', { name: 'Alice', age: 30 });
        console.log('Getting data...');
        const alice = store.get('/users/alice');
        console.log('✅ Retrieved:', alice);
        
        // Test 2: String operations
        console.log('\nTest 2: String operations...');
        store.setString('/users/bob/name', 'Bob Smith');
        const bobName = store.getString('/users/bob/name');
        console.log('✅ Bob name:', bobName);
        
        // Test 3: Enable authentication
        console.log('\nTest 3: Authentication...');
        const authEnabled = store.enableAuth('test-secret-key');
        console.log('✅ Auth enabled:', authEnabled);
        
        // Create a test token
        const token = store.createToken('alice', 'alice@example.com');
        console.log('✅ Token created:', token.substring(0, 20) + '...');
        
        // Test 4: Enable rules
        console.log('\nTest 4: Security rules...');
        const rulesEnabled = store.setupDefaultRules();
        console.log('✅ Rules enabled:', rulesEnabled);
        
        // Test 5: Rules enforcement
        console.log('\nTest 5: Rules enforcement...');
        
        try {
            // This should work - alice accessing her own data
            console.log('Testing alice access to her own profile...');
            store.set('/users/alice/profile', { bio: 'Software developer' }, token);
            console.log('✅ Alice can write to her profile');
            
            const profile = store.get('/users/alice/profile', token);
            console.log('✅ Alice can read her profile:', profile);
            
            // This should fail - alice accessing bob's private data
            try {
                console.log('Testing alice access to bob\'s profile...');
                store.set('/users/bob/profile', { bio: 'Hacker' }, token);
                console.log('❌ Alice should not be able to write to Bob\'s profile');
            } catch (error) {
                console.log('✅ Alice correctly denied access to Bob\'s profile:', error.message);
            }
            
            // This should work - public read access to names
            console.log('Testing public read access...');
            const publicName = store.getString('/users/bob/name'); // No token needed
            console.log('✅ Public read access to names works:', publicName);
            
        } catch (error) {
            console.log('❌ Rules test failed:', error.message);
            console.log('Token:', token);
        }
        
        // Test 6: Delete operations
        console.log('\nTest 6: Delete operations...');
        store.delete('/users/alice/profile', token);
        const deletedProfile = store.get('/users/alice/profile', token);
        console.log('✅ Profile deleted (should be null):', deletedProfile);
        
        console.log('\n🎉 All tests completed!');
        
    } catch (error) {
        console.error('❌ Test failed:', error);
    } finally {
        // Clean up
        store.close();
        if (fs.existsSync(testDataDir)) {
            fs.rmSync(testDataDir, { recursive: true });
        }
    }
}

// Run tests
runTests().catch(console.error);