#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function debugOptimization() {
    console.log('🔍 Debug: Analyzing optimization impact\n');
    
    // Clean up
    if (fs.existsSync('./debug-test')) {
        fs.rmSync('./debug-test', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './debug-test' 
    });
    
    // Test 1: Simple primitive write (should be fastest)
    console.log('Test 1: Simple primitive write');
    let start = Date.now();
    for (let i = 0; i < 1000; i++) {
        store.set(`/simple/${i}`, `value${i}`);
    }
    let elapsed = Date.now() - start;
    console.log(`  Simple primitives: ${Math.round(1000 / (elapsed / 1000))} ops/sec\n`);
    
    // Test 2: Small object write  
    console.log('Test 2: Small object write');
    start = Date.now();
    for (let i = 0; i < 1000; i++) {
        store.set(`/small/${i}`, { name: `User${i}`, age: i });
    }
    elapsed = Date.now() - start;
    console.log(`  Small objects: ${Math.round(1000 / (elapsed / 1000))} ops/sec\n`);
    
    // Test 3: Deep nested object (should show biggest improvement)
    console.log('Test 3: Deep nested object');
    start = Date.now();
    for (let i = 0; i < 1000; i++) {
        store.set(`/deep/${i}`, {
            level1: {
                level2: {
                    level3: {
                        level4: {
                            value: `deep${i}`
                        }
                    }
                }
            }
        });
    }
    elapsed = Date.now() - start;
    console.log(`  Deep objects: ${Math.round(1000 / (elapsed / 1000))} ops/sec\n`);
    
    // Test 4: Check if parent paths were actually eliminated
    console.log('Test 4: Checking database structure...');
    
    // This should work if optimization is correct
    store.set('/test/optimization/check', 'value');
    
    // Let's see what's actually in the database by trying to get intermediate paths
    try {
        const result1 = store.get('/test');
        console.log(`  /test exists: ${result1 ? 'YES' : 'NO'}`);
        
        const result2 = store.get('/test/optimization');
        console.log(`  /test/optimization exists: ${result2 ? 'YES' : 'NO'}`);
        
        const result3 = store.get('/test/optimization/check');
        console.log(`  /test/optimization/check = "${result3}"`);
        
    } catch (error) {
        console.log(`  Error reading paths: ${error.message}`);
    }
    
    store.close();
    console.log('\n✅ Debug analysis complete!');
}

debugOptimization().catch(console.error);