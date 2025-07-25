#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function simpleObjectTest() {
    console.log('🧪 Simple Object Test - Debug Reconstruction\n');
    
    const dbPath = './simple-object-test';
    
    // Clean slate
    if (fs.existsSync(dbPath)) {
        fs.rmSync(dbPath, { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: dbPath 
    });
    
    console.log('=== Writing object ===');
    store.set('/user', { name: 'John', age: 30 });
    console.log('✅ Object written: { name: "John", age: 30 }');
    
    console.log('\n=== Testing field access ===');
    const name = store.get('/user/name');
    const age = store.get('/user/age');
    console.log(`Field access - name: ${JSON.stringify(name)}`);
    console.log(`Field access - age: ${JSON.stringify(age)}`);
    
    console.log('\n=== Testing object reconstruction ===');
    const user = store.get('/user');
    console.log(`Object reconstruction: ${JSON.stringify(user)}`);
    console.log(`Type: ${typeof user}`);
    
    store.close();
}

simpleObjectTest().catch(console.error);