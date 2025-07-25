#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const { open } = require('lmdb');
const fs = require('fs');

async function testLMDBState() {
    console.log('🔬 LMDB State Analysis - Comprehensive Test\n');
    
    const dbPath = './lmdb-state-test';
    
    // Clean slate
    if (fs.existsSync(dbPath)) {
        fs.rmSync(dbPath, { recursive: true, force: true });
        console.log('✅ Cleaned previous database');
    }
    
    console.log('='.repeat(60));
    console.log('PHASE 1: Write data with ElkynStore');
    console.log('='.repeat(60));
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: dbPath 
    });
    
    // Test 1: Simple string
    console.log('\n📝 Test 1: Simple string');
    store.set('/simple', 'hello world');
    console.log('   Written: /simple = "hello world"');
    
    // Test 2: Simple object with string fields
    console.log('\n📝 Test 2: Object with string fields');
    store.set('/strings', { 
        name: 'John', 
        email: 'john@example.com' 
    });
    console.log('   Written: /strings = { name: "John", email: "john@example.com" }');
    
    // Test 3: Object with mixed types
    console.log('\n📝 Test 3: Object with mixed types');
    store.set('/mixed', { 
        name: 'Alice', 
        age: 30, 
        active: true,
        score: 85.5
    });
    console.log('   Written: /mixed = { name: "Alice", age: 30, active: true, score: 85.5 }');
    
    // Test 4: Nested object
    console.log('\n📝 Test 4: Nested object');
    store.set('/nested', {
        user: {
            name: 'Bob',
            age: 25
        },
        config: {
            theme: 'dark'
        }
    });
    console.log('   Written: /nested = { user: { name: "Bob", age: 25 }, config: { theme: "dark" } }');
    
    store.close();
    console.log('\n✅ ElkynStore closed');
    
    console.log('\n' + '='.repeat(60));
    console.log('PHASE 2: Read back with ElkynStore');
    console.log('='.repeat(60));
    
    const store2 = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: dbPath 
    });
    
    console.log('\n📖 ElkynStore reads:');
    console.log(`   /simple: ${JSON.stringify(store2.get('/simple'))}`);
    console.log(`   /strings/name: ${JSON.stringify(store2.get('/strings/name'))}`);
    console.log(`   /strings/email: ${JSON.stringify(store2.get('/strings/email'))}`);
    console.log(`   /mixed/name: ${JSON.stringify(store2.get('/mixed/name'))}`);
    console.log(`   /mixed/age: ${JSON.stringify(store2.get('/mixed/age'))}`);
    console.log(`   /mixed/active: ${JSON.stringify(store2.get('/mixed/active'))}`);
    console.log(`   /mixed/score: ${JSON.stringify(store2.get('/mixed/score'))}`);
    console.log(`   /nested/user/name: ${JSON.stringify(store2.get('/nested/user/name'))}`);
    console.log(`   /nested/user/age: ${JSON.stringify(store2.get('/nested/user/age'))}`);
    console.log(`   /nested/config/theme: ${JSON.stringify(store2.get('/nested/config/theme'))}`);
    
    console.log('\n📖 Object reconstruction:');
    console.log(`   /strings: ${JSON.stringify(store2.get('/strings'))}`);
    console.log(`   /mixed: ${JSON.stringify(store2.get('/mixed'))}`);
    console.log(`   /nested: ${JSON.stringify(store2.get('/nested'))}`);
    
    store2.close();
    
    console.log('\n' + '='.repeat(60));
    console.log('PHASE 3: Direct LMDB inspection');
    console.log('='.repeat(60));
    
    try {
        const lmdb = open({ path: dbPath });
        
        console.log('\n🔍 All keys in LMDB:');
        const allKeys = [];
        for (let { key, value } of lmdb.getRange()) {
            allKeys.push({ key, value });
            const displayValue = typeof value === 'string' ? 
                (value.length > 50 ? value.substring(0, 50) + '...' : value) : 
                '[binary ' + (value?.length || 0) + ' bytes]';
            console.log(`   "${key}" → ${displayValue}`);
        }
        
        console.log(`\n📊 Total keys found: ${allKeys.length}`);
        
        console.log('\n🔍 Expected vs Actual keys:');
        const expectedKeys = [
            '/simple',
            '/strings/name', '/strings/email',
            '/mixed/name', '/mixed/age', '/mixed/active', '/mixed/score',
            '/nested/user/name', '/nested/user/age', '/nested/config/theme'
        ];
        
        for (const expectedKey of expectedKeys) {
            const found = allKeys.find(k => k.key === expectedKey);
            if (found) {
                console.log(`   ✅ ${expectedKey} → FOUND`);
            } else {
                console.log(`   ❌ ${expectedKey} → MISSING`);
            }
        }
        
        console.log('\n🔍 Unexpected keys:');
        for (const { key } of allKeys) {
            if (!expectedKeys.includes(key)) {
                console.log(`   ⚠️  ${key} → UNEXPECTED`);
            }
        }
        
        lmdb.close();
        
    } catch (error) {
        console.error('❌ Error inspecting LMDB:', error.message);
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('ANALYSIS');
    console.log('='.repeat(60));
    
    console.log('\n📋 What this test reveals:');
    console.log('1. Which keys are actually written to LMDB');
    console.log('2. Whether object decomposition stops after first field');
    console.log('3. If the issue is with specific data types (number, boolean)');
    console.log('4. Whether nested objects work correctly');
    console.log('5. The exact LMDB storage state vs expectations');
}

testLMDBState().catch(console.error);