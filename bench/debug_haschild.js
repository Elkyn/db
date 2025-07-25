#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function debugHasChild() {
    console.log('🔍 Debug: hasAnyChild Function\n');
    
    if (fs.existsSync('./debug-haschild')) {
        fs.rmSync('./debug-haschild', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './debug-haschild' 
    });
    
    console.log('Setting object with multiple fields...');
    store.set('/user', { name: 'John', age: 30, active: true });
    
    console.log('\nTesting individual field access:');
    console.log(`  /user/name: ${store.get('/user/name')}`);
    console.log(`  /user/age: ${store.get('/user/age')}`);
    console.log(`  /user/active: ${store.get('/user/active')}`);
    
    console.log('\nTesting object reconstruction:');
    const fullUser = store.get('/user');
    console.log(`  /user: ${JSON.stringify(fullUser)}`);
    
    console.log('\nTesting nested object:');
    store.set('/profile', { 
        personal: { name: 'Alice', age: 25 },
        settings: { theme: 'dark', notifications: true }
    });
    
    console.log(`  /profile/personal/name: ${store.get('/profile/personal/name')}`);
    console.log(`  /profile/settings/theme: ${store.get('/profile/settings/theme')}`);
    console.log(`  /profile/personal: ${JSON.stringify(store.get('/profile/personal'))}`);
    console.log(`  /profile: ${JSON.stringify(store.get('/profile'))}`);
    
    store.close();
}

debugHasChild().catch(console.error);