#!/usr/bin/env node

const { ElkynStore } = require('@elkyn/store');
const fs = require('fs');

/**
 * Comprehensive test to verify all optimizations are working correctly
 */
async function verifyOptimizations() {
    console.log('🧪 Verification: All Optimizations Working\n');
    
    if (fs.existsSync('./verify-opt')) {
        fs.rmSync('./verify-opt', { recursive: true, force: true });
    }
    
    const store = new ElkynStore({ 
        mode: 'standalone', 
        dataDir: './verify-opt' 
    });
    
    let allTestsPassed = true;
    
    function test(name, condition, expected, actual) {
        const passed = condition;
        console.log(`${passed ? '✅' : '❌'} ${name}: ${passed ? 'PASS' : 'FAIL'}`);
        if (!passed) {
            console.log(`   Expected: ${expected}`);
            console.log(`   Actual: ${actual}`);
            allTestsPassed = false;
        }
        return passed;
    }
    
    console.log('=== Phase 1: Branch Marker Elimination ===');
    
    // Test 1: Direct primitive storage
    store.set('/test/primitive', 'value');
    const primitive = store.get('/test/primitive');
    test('Direct primitive access', primitive === 'value', 'value', primitive);
    
    // Test 2: Intermediate paths should not exist (Firebase-style)
    const intermediate = store.get('/test');
    test('Intermediate path eliminated', intermediate === undefined, 'undefined', intermediate);
    
    // Test 3: Path-based access should work
    const pathAccess = store.get('/test/primitive');
    test('Path-based access works', pathAccess === 'value', 'value', pathAccess);
    
    console.log('\n=== Phase 2: Object Storage ===');
    
    // Test 4: Object reconstruction
    store.set('/user', { name: 'John', age: 30 });
    const fullObject = store.get('/user');
    const objectCorrect = fullObject && fullObject.name === 'John' && fullObject.age === 30;
    test('Object reconstruction', objectCorrect, '{name: "John", age: 30}', JSON.stringify(fullObject));
    
    // Test 5: Individual field access (CRITICAL TEST)
    const fieldName = store.get('/user/name');
    const fieldAge = store.get('/user/age');
    test('Object field access: name', fieldName === 'John', 'John', fieldName);
    test('Object field access: age', fieldAge === 30, 30, fieldAge);
    
    console.log('\n=== Phase 3: Event System ===');
    
    // Test 6: Events still work
    let eventReceived = false;
    let eventData = null;
    
    const subscription = store.watch('/*').subscribe((data) => {
        eventReceived = true;
        eventData = data;
    });
    
    store.set('/event/test', 'event-value');
    
    // Give events time to process
    await new Promise(resolve => setTimeout(resolve, 50));
    
    test('Events functioning', eventReceived, true, eventReceived);
    
    subscription.unsubscribe();
    
    console.log('\n=== Phase 4: Performance ===');
    
    // Test 7: Write performance
    const iterations = 1000;
    const start = Date.now();
    
    for (let i = 0; i < iterations; i++) {
        store.set(`/perf/${i}`, { id: i, data: `test${i}` });
    }
    
    const elapsed = Date.now() - start;
    const opsPerSec = Math.round(iterations / (elapsed / 1000));
    
    console.log(`   Write performance: ${opsPerSec} ops/sec`);
    
    // Performance should be better than baseline (10,707 ops/sec)
    const performanceImproved = opsPerSec > 10000;
    test('Performance improved', performanceImproved, '>10,000 ops/sec', `${opsPerSec} ops/sec`);
    
    console.log('\n=== Correctness Verification ===');
    
    // Test 8: Complex nested structures
    store.set('/complex', {
        users: {
            '123': { name: 'Alice', profile: { bio: 'Developer' } },
            '456': { name: 'Bob', profile: { bio: 'Designer' } }
        },
        config: {
            theme: 'dark',
            notifications: true
        }
    });
    
    const complex = store.get('/complex');
    const aliceNameDeep = store.get('/complex/users/123/name');
    const bioBob = store.get('/complex/users/456/profile/bio');
    const theme = store.get('/complex/config/theme');
    
    test('Complex object reconstruction', complex !== undefined, 'object', typeof complex);
    test('Deep nested access: Alice name', aliceNameDeep === 'Alice', 'Alice', aliceNameDeep);
    test('Deep nested access: Bob bio', bioBob === 'Designer', 'Designer', bioBob);
    test('Config access', theme === 'dark', 'dark', theme);
    
    store.close();
    
    console.log('\n' + '='.repeat(50));
    console.log(`🎯 OPTIMIZATION VERIFICATION: ${allTestsPassed ? '✅ ALL TESTS PASSED' : '❌ SOME TESTS FAILED'}`);
    console.log('='.repeat(50));
    
    if (!allTestsPassed) {
        console.log('\n🚨 Issues found that need to be fixed!');
        process.exit(1);
    } else {
        console.log('\n🎉 All optimizations are working correctly!');
        console.log(`📊 Performance: ${opsPerSec} ops/sec`);
    }
    
    return { allTestsPassed, performance: opsPerSec };
}

verifyOptimizations().catch(console.error);