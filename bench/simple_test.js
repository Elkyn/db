#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function simpleTest() {
    console.log('🔍 Simple Test: Primitives vs Objects\n');
    
    if (fs.existsSync('./simple-test')) {
        fs.rmSync('./simple-test', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './simple-test' 
    });
    
    console.log('Test 1: Primitive values');
    store.set('/primitive1', 'hello');
    store.set('/primitive2', 42);
    store.set('/primitive3', true);
    
    console.log(`  /primitive1: ${store.get('/primitive1')}`);
    console.log(`  /primitive2: ${store.get('/primitive2')}`);
    console.log(`  /primitive3: ${store.get('/primitive3')}`);
    
    console.log('\nTest 2: Single-field object');
    store.set('/obj1', { field: 'value' });
    
    console.log(`  /obj1: ${JSON.stringify(store.get('/obj1'))}`);
    console.log(`  /obj1/field: ${store.get('/obj1/field')}`);
    
    console.log('\nTest 3: Multi-field object');
    store.set('/obj2', { a: 1, b: 2 });
    
    console.log(`  /obj2: ${JSON.stringify(store.get('/obj2'))}`);
    console.log(`  /obj2/a: ${store.get('/obj2/a')}`);
    console.log(`  /obj2/b: ${store.get('/obj2/b')}`);
    
    store.close();
}

simpleTest().catch(console.error);