#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function debugBatch() {
    console.log('🔍 Debug: Batch Write Issues\n');
    
    if (fs.existsSync('./debug-batch')) {
        fs.rmSync('./debug-batch', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './debug-batch' 
    });
    
    // Simple test
    console.log('Test 1: Simple object');
    store.set('/simple', { name: 'John', age: 30 });
    
    console.log('Reads:');
    console.log(`  /simple: ${JSON.stringify(store.get('/simple'))}`);
    console.log(`  /simple/name: ${store.get('/simple/name')}`);
    console.log(`  /simple/age: ${store.get('/simple/age')}`);
    
    console.log('\nTest 2: Deep nesting');
    store.set('/deep', { level1: { level2: { value: 'deep' } } });
    
    console.log('Reads:');
    console.log(`  /deep: ${JSON.stringify(store.get('/deep'))}`);
    console.log(`  /deep/level1: ${JSON.stringify(store.get('/deep/level1'))}`);
    console.log(`  /deep/level1/level2: ${JSON.stringify(store.get('/deep/level1/level2'))}`);
    console.log(`  /deep/level1/level2/value: ${store.get('/deep/level1/level2/value')}`);
    
    store.close();
}

debugBatch().catch(console.error);