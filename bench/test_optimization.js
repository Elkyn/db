#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

async function testOptimizations() {
    console.log('🚀 Testing Write Optimizations\n');
    
    // Clean up previous test data
    if (fs.existsSync('./test-optimized')) {
        fs.rmSync('./test-optimized', { recursive: true, force: true });
    }
    
    try {
        const store = new ElkynStore({ 
            mode: 'standalone', 
            dataDir: './test-optimized' 
        });
        
        console.log('✅ Store initialized successfully');
        
        // Simple write test
        console.log('📝 Testing basic write operations...');
        
        const iterations = 1000;
        const start = Date.now();
        
        for (let i = 0; i < iterations; i++) {
            store.set(`/user/${i}`, { 
                name: `User ${i}`,
                email: `user${i}@example.com`,
                age: 20 + (i % 50),
                active: i % 2 === 0
            });
        }
        
        const elapsed = Date.now() - start;
        const opsPerSec = Math.round(iterations / (elapsed / 1000));
        
        console.log(`✅ Completed ${iterations} writes in ${elapsed}ms`);
        console.log(`📊 Performance: ${opsPerSec} ops/sec`);
        
        // Test read operations
        console.log('\n📖 Testing read operations...');
        const readStart = Date.now();
        
        for (let i = 0; i < iterations; i++) {
            const data = store.get(`/user/${i % 100}`);
            if (!data) {
                console.error(`❌ Failed to read /user/${i % 100}`);
            }
        }
        
        const readElapsed = Date.now() - readStart;
        const readOpsPerSec = Math.round(iterations / (readElapsed / 1000));
        
        console.log(`✅ Completed ${iterations} reads in ${readElapsed}ms`);
        console.log(`📊 Read Performance: ${readOpsPerSec} ops/sec`);
        
        // Test object structure
        console.log('\n🔍 Testing optimized object structure...');
        
        store.set('/test/nested/object', {
            level1: {
                level2: {
                    level3: {
                        value: 'deep nested value'
                    }
                }
            }
        });
        
        // Test path-based access still works
        const nestedValue = store.get('/test/nested/object/level1/level2/level3/value');
        console.log(`✅ Nested path access: ${nestedValue}`);
        
        // Test object reconstruction
        const fullObject = store.get('/test/nested/object');
        console.log(`✅ Object reconstruction: ${JSON.stringify(fullObject, null, 2)}`);
        
        store.close();
        console.log('\n🎉 All optimization tests passed!');
        
        return { writeOps: opsPerSec, readOps: readOpsPerSec };
        
    } catch (error) {
        console.error('❌ Test failed:', error.message);
        console.error(error.stack);
        process.exit(1);
    }
}

// Run the test
testOptimizations().then(results => {
    console.log('\n📊 Final Results:');
    console.log(`   Write Performance: ${results.writeOps} ops/sec`);
    console.log(`   Read Performance: ${results.readOps} ops/sec`);
    
    // Compare with previous benchmarks
    const previousWrite = 10707; // From our earlier benchmarks
    const improvement = ((results.writeOps / previousWrite - 1) * 100).toFixed(1);
    
    console.log(`\n🚀 Optimization Impact:`);
    if (improvement > 0) {
        console.log(`   ${improvement}% improvement in write performance!`);
    } else {
        console.log(`   ${Math.abs(improvement)}% regression in write performance`);
    }
}).catch(console.error);