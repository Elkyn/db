#!/usr/bin/env node

const { open } = require('lmdb');

async function inspectKeys() {
    console.log('🔍 Inspecting LMDB Keys\n');
    
    const db = open({ path: './test-strings' });
    
    console.log('All keys in database:');
    
    for (let { key, value } of db.getRange()) {
        const valueStr = typeof value === 'string' ? value.substring(0, 50) : '[binary]';
        console.log(`  "${key}" -> ${valueStr}`);
    }
    
    console.log('\nChecking prefix search for "/user/":');
    const prefix = '/user/';
    let found = false;
    
    for (let { key } of db.getRange()) {
        if (key.startsWith(prefix)) {
            console.log(`  Found child: "${key}"`);
            found = true;
        }
    }
    
    if (!found) {
        console.log('  No children found with prefix "/user/"');
    }
    
    db.close();
}

inspectKeys().catch(console.error);