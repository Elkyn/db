#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function testStringsOnly() {
    console.log('🧪 Test: String Fields Only\n');
    
    if (fs.existsSync('./test-strings')) {
        fs.rmSync('./test-strings', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './test-strings' 
    });
    
    console.log('Setting object with string fields only...');
    store.set('/user', { 
        name: 'John', 
        email: 'john@example.com',
        role: 'admin'
    });
    
    console.log('\nTesting individual field access:');
    console.log(`  /user/name: ${store.get('/user/name')}`);
    console.log(`  /user/email: ${store.get('/user/email')}`);
    console.log(`  /user/role: ${store.get('/user/role')}`);
    
    console.log('\nTesting object reconstruction:');
    const fullUser = store.get('/user');
    console.log(`  /user: ${JSON.stringify(fullUser)}`);
    
    store.close();
}

testStringsOnly().catch(console.error);