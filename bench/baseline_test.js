#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function baselineTest() {
    console.log('🎯 Baseline Performance Test\n');
    
    const dbPath = './baseline-test';
    
    // Clean slate
    if (fs.existsSync(dbPath)) {
        fs.rmSync(dbPath, { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: dbPath 
    });
    
    // Test 1: Simple write performance (like the original 10,707 ops/sec test)
    console.log('=== Simple Write Performance ===');
    const iterations = 1000;
    const start = Date.now();
    
    for (let i = 0; i < iterations; i++) {
        store.set(`/perf/${i}`, { data: 'test', id: i });
    }
    
    const elapsed = Date.now() - start;
    const opsPerSec = Math.round((iterations / elapsed) * 1000);
    
    console.log(`Iterations: ${iterations}`);
    console.log(`Time: ${elapsed}ms`);
    console.log(`Performance: ${opsPerSec} ops/sec`);
    
    // Test 2: Compare with original working version behavior
    console.log('\n=== Functional Test ===');
    store.set('/test/obj', { name: 'John', age: 30, active: true });
    
    const name = store.get('/test/obj/name');
    const age = store.get('/test/obj/age');
    const active = store.get('/test/obj/active');
    const obj = store.get('/test/obj');
    
    console.log(`Field access - name: ${JSON.stringify(name)}`);
    console.log(`Field access - age: ${JSON.stringify(age)}`);  
    console.log(`Field access - active: ${JSON.stringify(active)}`);
    console.log(`Object reconstruction: ${JSON.stringify(obj)}`);
    
    store.close();
    
    console.log('\n=== Analysis ===');
    if (opsPerSec < 8000) {
        console.log('❌ Performance regression detected!');
        console.log('   Something is causing significant slowdown');
    } else if (opsPerSec > 12000) {
        console.log('✅ Performance improvement achieved!');
    } else {
        console.log('⚠️  Performance similar to original');
    }
}

baselineTest().catch(console.error);