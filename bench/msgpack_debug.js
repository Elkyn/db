#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function debugMessagePack() {
    console.log('🔬 MessagePack Debug Test\n');
    
    const dbPath = './msgpack-debug';
    
    // Clean slate
    if (fs.existsSync(dbPath)) {
        fs.rmSync(dbPath, { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: dbPath 
    });
    
    console.log('='.repeat(60));
    console.log('TEST: Individual primitive writes vs reads');
    console.log('='.repeat(60));
    
    // Test each type individually to isolate the issue
    console.log('\n📝 Test 1: String');
    store.set('/test/string', 'hello');
    const string_result = store.get('/test/string');
    console.log(`   Write: "hello" → Read: ${JSON.stringify(string_result)}`);
    
    console.log('\n📝 Test 2: Number');
    store.set('/test/number', 42);
    const number_result = store.get('/test/number');
    console.log(`   Write: 42 → Read: ${JSON.stringify(number_result)}`);
    
    console.log('\n📝 Test 3: Boolean');
    store.set('/test/boolean', true);
    const boolean_result = store.get('/test/boolean');
    console.log(`   Write: true → Read: ${JSON.stringify(boolean_result)}`);
    
    console.log('\n📝 Test 4: Float');
    store.set('/test/float', 3.14);
    const float_result = store.get('/test/float');
    console.log(`   Write: 3.14 → Read: ${JSON.stringify(float_result)}`);
    
    console.log('\n📝 Test 5: Object with single string field');
    store.set('/test/obj_string', { name: 'test' });
    const obj_string_field = store.get('/test/obj_string/name');
    console.log(`   Write: { name: 'test' } → Read /name: ${JSON.stringify(obj_string_field)}`);
    
    console.log('\n📝 Test 6: Object with single number field');
    store.set('/test/obj_number', { age: 25 });
    const obj_number_field = store.get('/test/obj_number/age');
    console.log(`   Write: { age: 25 } → Read /age: ${JSON.stringify(obj_number_field)}`);
    
    console.log('\n📝 Test 7: Object with single boolean field');
    store.set('/test/obj_bool', { active: false });
    const obj_bool_field = store.get('/test/obj_bool/active');
    console.log(`   Write: { active: false } → Read /active: ${JSON.stringify(obj_bool_field)}`);
    
    store.close();
    
    console.log('\n' + '='.repeat(60));
    console.log('ANALYSIS');
    console.log('='.repeat(60));
    
    console.log('\n📊 Results Summary:');
    console.log(`   String primitive: ${string_result !== undefined ? '✅' : '❌'}`);
    console.log(`   Number primitive: ${number_result !== undefined ? '✅' : '❌'}`);
    console.log(`   Boolean primitive: ${boolean_result !== undefined ? '✅' : '❌'}`);
    console.log(`   Float primitive: ${float_result !== undefined ? '✅' : '❌'}`);
    console.log(`   String in object: ${obj_string_field !== undefined ? '✅' : '❌'}`);
    console.log(`   Number in object: ${obj_number_field !== undefined ? '✅' : '❌'}`);
    console.log(`   Boolean in object: ${obj_bool_field !== undefined ? '✅' : '❌'}`);
    
    console.log('\n🎯 This tells us:');
    console.log('   - If primitives work but object fields fail → Issue is in object decomposition read path');
    console.log('   - If number/boolean primitives fail → Issue is in MessagePack serialization/deserialization');
    console.log('   - If only strings work → Issue is with non-string MessagePack handling');
}

debugMessagePack().catch(console.error);