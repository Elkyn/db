#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function numberTest() {
    console.log('🧪 Number Test - Direct Primitive\n');
    
    const dbPath = './number-test';
    
    // Clean slate
    if (fs.existsSync(dbPath)) {
        fs.rmSync(dbPath, { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: dbPath 
    });
    
    console.log('=== Testing direct number ===');
    store.set('/number', 42);
    const result = store.get('/number');
    console.log(`Direct number: ${JSON.stringify(result)} (type: ${typeof result})`);
    
    console.log('\n=== Testing direct boolean ===');
    store.set('/boolean', true);
    const boolResult = store.get('/boolean');
    console.log(`Direct boolean: ${JSON.stringify(boolResult)} (type: ${typeof boolResult})`);
    
    console.log('\n=== Testing direct string ===');
    store.set('/string', "hello");
    const stringResult = store.get('/string');
    console.log(`Direct string: ${JSON.stringify(stringResult)} (type: ${typeof stringResult})`);
    
    store.close();
}

numberTest().catch(console.error);