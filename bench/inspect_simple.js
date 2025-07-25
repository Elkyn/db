#!/usr/bin/env node

const { open } = require('lmdb');

async function inspectSimple() {
    console.log('🔍 Inspecting final-debug database\n');
    
    try {
        const db = open({ path: './final-debug' });
        
        console.log('All keys in database:');
        
        let count = 0;
        for (let { key, value } of db.getRange()) {
            console.log(`  "${key}" -> "${typeof value === 'string' ? value : '[binary]'}"`);
            count++;
        }
        
        console.log(`\nTotal keys: ${count}`);
        
        // Try direct access to expected keys
        console.log('\nDirect key lookups:');
        console.log(`  /profile/name: ${db.get('/profile/name') || 'NOT_FOUND'}`);
        console.log(`  /profile/age: ${db.get('/profile/age') || 'NOT_FOUND'}`);
        console.log(`  /users/123/name: ${db.get('/users/123/name') || 'NOT_FOUND'}`);
        
        db.close();
    } catch (error) {
        console.error('Error:', error.message);
    }
}

inspectSimple().catch(console.error);