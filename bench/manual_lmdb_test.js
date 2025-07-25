#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const { open } = require('lmdb');
const fs = require('fs');

async function testManualLMDB() {
    console.log('🧪 Manual LMDB Test - Bypass Elkyn Write Path\n');
    
    const dbPath = './manual-lmdb-test';
    
    // Clean slate
    if (fs.existsSync(dbPath)) {
        fs.rmSync(dbPath, { recursive: true, force: true });
        console.log('✅ Cleaned previous database');
    }
    
    console.log('='.repeat(60));
    console.log('PHASE 1: Write directly to LMDB');
    console.log('='.repeat(60));
    
    const lmdb = open({ path: dbPath });
    
    // Test 1: Write string directly to LMDB (should work)
    console.log('\n📝 Test 1: Manual string write');
    lmdb.put('/manual/string', 'hello manual');
    console.log('   Written: /manual/string = "hello manual"');
    
    // Test 2: Write number as JSON string (simulating what JS might send)
    console.log('\n📝 Test 2: Manual number as JSON');
    lmdb.put('/manual/number_json', '30');
    console.log('   Written: /manual/number_json = "30" (JSON string)');
    
    // Test 3: Write boolean as JSON string
    console.log('\n📝 Test 3: Manual boolean as JSON');
    lmdb.put('/manual/boolean_json', 'true');
    console.log('   Written: /manual/boolean_json = "true" (JSON string)');
    
    // Test 4: Write actual JSON object string
    console.log('\n📝 Test 4: Manual JSON object');
    lmdb.put('/manual/object_json', '{"name":"test","age":25}');
    console.log('   Written: /manual/object_json = JSON object string');
    
    console.log('\n🔍 All keys written to LMDB:');
    for (let { key, value } of lmdb.getRange()) {
        console.log(`   "${key}" → "${value}"`);
    }
    
    lmdb.close();
    
    console.log('\n' + '='.repeat(60));
    console.log('PHASE 2: Read with ElkynStore');
    console.log('='.repeat(60));
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: dbPath 
    });
    
    console.log('\n📖 ElkynStore reads from manual LMDB data:');
    console.log(`   /manual/string: ${JSON.stringify(store.get('/manual/string'))}`);
    console.log(`   /manual/number_json: ${JSON.stringify(store.get('/manual/number_json'))}`);
    console.log(`   /manual/boolean_json: ${JSON.stringify(store.get('/manual/boolean_json'))}`);
    console.log(`   /manual/object_json: ${JSON.stringify(store.get('/manual/object_json'))}`);
    
    console.log('\n' + '='.repeat(60));
    console.log('PHASE 3: Write with Elkyn, inspect MessagePack');
    console.log('='.repeat(60));
    
    // Write some values with Elkyn and inspect what MessagePack looks like
    store.set('/elkyn/string', 'hello elkyn');
    store.set('/elkyn/number', 42);
    store.set('/elkyn/boolean', true);
    
    store.close();
    
    // Reopen LMDB to inspect what Elkyn actually wrote
    const lmdb2 = open({ path: dbPath });
    
    console.log('\n🔍 Raw LMDB data after Elkyn writes:');
    for (let { key, value } of lmdb2.getRange()) {
        if (key.startsWith('/elkyn/')) {
            const bytes = Array.from(value).map(b => '0x' + b.toString(16).padStart(2, '0')).join(' ');
            console.log(`   "${key}" → [${bytes}] (${value.length} bytes)`);
        }
    }
    
    lmdb2.close();
    
    console.log('\n' + '='.repeat(60));
    console.log('PHASE 4: Read back Elkyn data');
    console.log('='.repeat(60));
    
    const store2 = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: dbPath 
    });
    
    console.log('\n📖 ElkynStore reads its own data:');
    console.log(`   /elkyn/string: ${JSON.stringify(store2.get('/elkyn/string'))}`);
    console.log(`   /elkyn/number: ${JSON.stringify(store2.get('/elkyn/number'))}`);
    console.log(`   /elkyn/boolean: ${JSON.stringify(store2.get('/elkyn/boolean'))}`);
    
    store2.close();
    
    console.log('\n' + '='.repeat(60));
    console.log('ANALYSIS');
    console.log('='.repeat(60));
    
    console.log('\n📋 What this reveals:');
    console.log('1. Whether Elkyn can read manually inserted LMDB data');
    console.log('2. What the actual MessagePack bytes look like');
    console.log('3. If the issue is in write (MessagePack encoding) or read (MessagePack decoding)');
    console.log('4. Whether the issue is with specific data types');
}

testManualLMDB().catch(console.error);