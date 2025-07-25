const { ElkynStore } = require('./index.js');
const fs = require('fs');
const path = require('path');

const NUM_READS = 100000;

// Create test directory
const dataDir = path.join(__dirname, 'data_bench_read');
if (fs.existsSync(dataDir)) {
    fs.rmSync(dataDir, { recursive: true });
}
fs.mkdirSync(dataDir);

async function setupData(db) {
    console.log('Setting up test data...');
    
    // Write different types of data
    db.set('/test/string1', 'Hello World');
    db.set('/test/string2', 'A much longer string with more content to test performance');
    db.set('/test/number1', 42);
    db.set('/test/number2', 3.14159);
    db.set('/test/bool1', true);
    db.set('/test/bool2', false);
    db.set('/test/null', null);
    
    // Complex object for comparison
    db.set('/test/object', {
        name: 'Test Object',
        value: 123,
        nested: { a: 1, b: 2 }
    });
    
    console.log('Test data setup complete\n');
}

async function benchGetBinary(db) {
    console.log('Benchmarking getBinary (MessagePack deserialization)...');
    const startTime = Date.now();
    
    for (let i = 0; i < NUM_READS; i++) {
        // Rotate through different values
        const keys = ['/test/string1', '/test/number1', '/test/bool1', '/test/null'];
        const key = keys[i % keys.length];
        db.getBinary(key);
    }
    
    const duration = Date.now() - startTime;
    const opsPerSec = (NUM_READS / (duration / 1000)).toFixed(0);
    
    console.log(`  ${NUM_READS} reads in ${duration}ms`);
    console.log(`  ${opsPerSec} ops/sec`);
    
    return opsPerSec;
}

async function benchGetRaw(db) {
    console.log('\nBenchmarking getRaw (zero-copy for primitives)...');
    const startTime = Date.now();
    
    for (let i = 0; i < NUM_READS; i++) {
        // Rotate through different values
        const keys = ['/test/string1', '/test/number1', '/test/bool1', '/test/null'];
        const key = keys[i % keys.length];
        db.getRaw(key);
    }
    
    const duration = Date.now() - startTime;
    const opsPerSec = (NUM_READS / (duration / 1000)).toFixed(0);
    
    console.log(`  ${NUM_READS} reads in ${duration}ms`);
    console.log(`  ${opsPerSec} ops/sec`);
    
    return opsPerSec;
}

async function benchComplexReads(db) {
    console.log('\nBenchmarking complex object reads...');
    
    // Test getBinary
    console.log('  getBinary (object):');
    let startTime = Date.now();
    
    for (let i = 0; i < NUM_READS / 10; i++) {
        db.getBinary('/test/object');
    }
    
    let duration = Date.now() - startTime;
    let opsPerSec = ((NUM_READS / 10) / (duration / 1000)).toFixed(0);
    console.log(`    ${NUM_READS / 10} reads in ${duration}ms`);
    console.log(`    ${opsPerSec} ops/sec`);
    
    const binaryOps = opsPerSec;
    
    // Test getRaw (which falls back to MessagePack for complex types)
    console.log('  getRaw (object):');
    startTime = Date.now();
    
    for (let i = 0; i < NUM_READS / 10; i++) {
        db.getRaw('/test/object');
    }
    
    duration = Date.now() - startTime;
    opsPerSec = ((NUM_READS / 10) / (duration / 1000)).toFixed(0);
    console.log(`    ${NUM_READS / 10} reads in ${duration}ms`);
    console.log(`    ${opsPerSec} ops/sec`);
    
    return { binaryOps, rawOps: opsPerSec };
}

async function main() {
    console.log(`Elkyn DB Zero-Copy Read Benchmark`);
    console.log(`==================================`);
    console.log(`Reads per test: ${NUM_READS}\n`);
    
    const db = new ElkynStore(dataDir);
    
    try {
        await setupData(db);
        
        const binaryOps = await benchGetBinary(db);
        const rawOps = await benchGetRaw(db);
        const complexResults = await benchComplexReads(db);
        
        console.log('\nSummary:');
        console.log('--------');
        console.log(`Primitive reads (getBinary):  ${binaryOps} ops/sec`);
        console.log(`Primitive reads (getRaw):     ${rawOps} ops/sec`);
        console.log(`Complex reads (getBinary):    ${complexResults.binaryOps} ops/sec`);
        console.log(`Complex reads (getRaw):       ${complexResults.rawOps} ops/sec`);
        
        const improvement = (parseFloat(rawOps) / parseFloat(binaryOps)).toFixed(2);
        console.log(`\nZero-copy improvement for primitives: ${improvement}x`);
        
    } catch (error) {
        console.error('Benchmark failed:', error);
    } finally {
        db.close();
        // Clean up
        fs.rmSync(dataDir, { recursive: true });
    }
}

main().catch(console.error);