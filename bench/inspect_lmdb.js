#!/usr/bin/env node

const { open } = require('lmdb');

async function inspectLMDB() {
    console.log('🔍 Inspecting LMDB contents after batch writes\n');
    
    const db = open({ path: './debug-batch' });
    
    console.log('All keys in database:');
    
    let count = 0;
    for (let { key, value } of db.getRange()) {
        console.log(`  "${key}" -> "${value}"`);
        count++;
        if (count > 20) {
            console.log('  ... (truncated, too many keys)');
            break;
        }
    }
    
    console.log(`\nTotal keys found: ${count}${count > 20 ? '+' : ''}`);
    
    db.close();
}

inspectLMDB().catch(console.error);