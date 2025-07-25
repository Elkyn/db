#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function minimalDebug() {
    console.log('🔬 Minimal Debug: Object Decomposition\n');
    
    if (fs.existsSync('./minimal-debug')) {
        fs.rmSync('./minimal-debug', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './minimal-debug' 
    });
    
    console.log('Step 1: Setting simple object...');
    store.set('/obj', { key: 'value' });
    console.log('✅ Object set completed');
    
    console.log('\nStep 2: Reading full object...');
    const full = store.get('/obj');
    console.log(`Full object: ${JSON.stringify(full)}`);
    
    console.log('\nStep 3: Reading individual field...');
    const field = store.get('/obj/key');
    console.log(`Field /obj/key: ${field}`);
    
    console.log('\nStep 4: Setting primitive directly...');
    store.set('/direct', 'direct-value');
    const direct = store.get('/direct');
    console.log(`Direct primitive: ${direct}`);
    
    store.close();
    
    console.log('\n=== Analysis ===');
    console.log('If full object works but field fails:');
    console.log('  → Object decomposition is not happening');
    console.log('If both fail:');
    console.log('  → Storage is completely broken');
}

minimalDebug().catch(console.error);