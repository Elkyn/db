#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function simpleInspect() {
    console.log('🔍 Simple Key Inspection\n');
    
    if (fs.existsSync('./simple-inspect')) {
        fs.rmSync('./simple-inspect', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './simple-inspect' 
    });
    
    console.log('Setting object and testing...');
    store.set('/test', { a: 'alpha', b: 'beta' });
    
    console.log('\nDirect field tests:');
    console.log(`  /test/a: ${store.get('/test/a')}`);
    console.log(`  /test/b: ${store.get('/test/b')}`);
    
    console.log('\nObject reconstruction test:');
    const obj = store.get('/test');
    console.log(`  /test: ${obj ? JSON.stringify(obj) : 'undefined'}`);
    
    console.log('\nPath existence tests:');
    console.log(`  /test exists: ${store.exists('/test')}`);
    console.log(`  /test/a exists: ${store.exists('/test/a')}`);
    console.log(`  /test/b exists: ${store.exists('/test/b')}`);
    
    store.close();
}

simpleInspect().catch(console.error);