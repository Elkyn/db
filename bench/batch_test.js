#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function testBatchWrites() {
    console.log('🚀 Testing Batch Write Optimization\n');
    
    // Clean up
    if (fs.existsSync('./batch-test')) {
        fs.rmSync('./batch-test', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './batch-test' 
    });
    
    // Test scenario: objects with many fields (should benefit most from batching)
    console.log('Test: Large objects (10 fields each)');
    
    const iterations = 1000;
    const start = Date.now();
    
    for (let i = 0; i < iterations; i++) {
        store.set(`/user/${i}`, {
            id: i,
            name: `User ${i}`,
            email: `user${i}@example.com`,
            age: 20 + (i % 50),
            department: `Dept ${i % 10}`,
            active: i % 2 === 0,
            created: new Date().toISOString(),
            score: Math.random() * 100,
            level: i % 5 + 1,
            bio: `This is user ${i}'s biography with some text to make it interesting.`
        });
    }
    
    const elapsed = Date.now() - start;
    const opsPerSec = Math.round(iterations / (elapsed / 1000));
    
    console.log(`✅ Completed ${iterations} large object writes in ${elapsed}ms`);
    console.log(`📊 Performance: ${opsPerSec} ops/sec`);
    console.log(`💾 Each object had 10 fields = ${iterations * 10} total LMDB operations`);
    console.log(`⚡ Effective rate: ${Math.round(iterations * 10 / (elapsed / 1000))} LMDB ops/sec\n`);
    
    // Test read performance to ensure structure is correct
    console.log('Verifying batch write correctness...');
    
    const testUser = store.get('/user/0');
    console.log(`✅ Full object read: ${testUser ? 'SUCCESS' : 'FAILED'}`);
    
    const testField = store.get('/user/0/name');
    console.log(`✅ Field access: ${testField} ${testField === 'User 0' ? 'SUCCESS' : 'FAILED'}`);
    
    const testNested = store.get('/user/0/bio');
    console.log(`✅ Nested field: ${testNested ? 'SUCCESS' : 'FAILED'}`);
    
    store.close();
    
    return opsPerSec;
}

testBatchWrites().then(result => {
    console.log(`\n🎯 Batch Write Performance: ${result} ops/sec`);
    console.log('Expected improvement: 2-3x for multi-field objects');
}).catch(console.error);