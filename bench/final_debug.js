#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function finalDebug() {
    console.log('🔬 Final Debug: Primitive vs Object Field Access\n');
    
    if (fs.existsSync('./final-debug')) {
        fs.rmSync('./final-debug', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './final-debug' 
    });
    
    console.log('=== Test 1: Direct primitive assignment ===');
    store.set('/users/123/name', 'John');  // Direct primitive
    store.set('/users/123/age', 30);       // Direct primitive
    
    console.log(`/users/123/name: ${store.get('/users/123/name')}`);
    console.log(`/users/123/age: ${store.get('/users/123/age')}`);
    
    console.log('\n=== Test 2: Object assignment (decomposed) ===');
    store.set('/profile', { name: 'Alice', age: 25 });  // Object -> should decompose
    
    console.log(`/profile: ${JSON.stringify(store.get('/profile'))}`);
    console.log(`/profile/name: ${store.get('/profile/name')}`);
    console.log(`/profile/age: ${store.get('/profile/age')}`);
    
    console.log('\n=== Analysis ===');
    console.log('If Test 1 works but Test 2 fails:');
    console.log('  → Object decomposition is broken');
    console.log('If both fail:');  
    console.log('  → All field access is broken');
    console.log('If both work:');
    console.log('  → Optimization is working correctly');
    
    store.close();
}

finalDebug().catch(console.error);