const { ElkynStore } = require('./index.js');
const fs = require('fs');
const path = require('path');

const NUM_WRITES = 1000;

// Create test directory
const dataDir = path.join(__dirname, 'data_bench_write_queue');
if (fs.existsSync(dataDir)) {
    fs.rmSync(dataDir, { recursive: true });
}
fs.mkdirSync(dataDir);

async function benchSyncWrites() {
    const db = new ElkynStore(dataDir);
    
    console.log('Benchmarking synchronous writes...');
    const startTime = Date.now();
    
    for (let i = 0; i < NUM_WRITES; i++) {
        db.set(`/bench/sync/item${i}`, { index: i, data: `test-${i}` });
    }
    
    const endTime = Date.now();
    const duration = endTime - startTime;
    const opsPerSec = (NUM_WRITES / (duration / 1000)).toFixed(0);
    
    console.log(`  ${NUM_WRITES} sync writes in ${duration}ms`);
    console.log(`  ${opsPerSec} ops/sec`);
    
    db.close();
    return opsPerSec;
}

async function benchAsyncWrites() {
    const db = new ElkynStore(dataDir);
    db.enableWriteQueue();
    
    console.log('\nBenchmarking async writes (with write queue)...');
    const startTime = Date.now();
    
    const writeIds = [];
    for (let i = 0; i < NUM_WRITES; i++) {
        const id = db.setAsync(`/bench/async/item${i}`, { index: i, data: `test-${i}` });
        writeIds.push(id);
    }
    
    const queueTime = Date.now() - startTime;
    console.log(`  Queued ${NUM_WRITES} writes in ${queueTime}ms`);
    
    // Wait for all writes to complete
    const waitStart = Date.now();
    for (const id of writeIds) {
        await db.waitForWrite(id);
    }
    const waitTime = Date.now() - waitStart;
    
    const totalTime = Date.now() - startTime;
    const opsPerSec = (NUM_WRITES / (totalTime / 1000)).toFixed(0);
    
    console.log(`  Wait time: ${waitTime}ms`);
    console.log(`  Total time: ${totalTime}ms`);
    console.log(`  ${opsPerSec} ops/sec (effective)`);
    
    db.close();
    return opsPerSec;
}

async function benchAsyncWritesNoBatching() {
    const db = new ElkynStore(dataDir);
    db.enableWriteQueue();
    
    console.log('\nBenchmarking async writes (queue only, no wait)...');
    const startTime = Date.now();
    
    for (let i = 0; i < NUM_WRITES; i++) {
        db.setAsync(`/bench/queue/item${i}`, { index: i, data: `test-${i}` });
    }
    
    const duration = Date.now() - startTime;
    const opsPerSec = (NUM_WRITES / (duration / 1000)).toFixed(0);
    
    console.log(`  ${NUM_WRITES} writes queued in ${duration}ms`);
    console.log(`  ${opsPerSec} ops/sec (queue throughput)`);
    
    // Give some time for writes to complete before closing
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    db.close();
    return opsPerSec;
}

async function main() {
    console.log(`Elkyn DB Write Queue Benchmark`);
    console.log(`==============================`);
    console.log(`Writes per test: ${NUM_WRITES}\n`);
    
    try {
        const syncOps = await benchSyncWrites();
        const asyncOps = await benchAsyncWrites();
        const queueOps = await benchAsyncWritesNoBatching();
        
        console.log('\nSummary:');
        console.log('--------');
        console.log(`Synchronous writes:    ${syncOps} ops/sec`);
        console.log(`Async writes (full):   ${asyncOps} ops/sec`);
        console.log(`Async writes (queue):  ${queueOps} ops/sec`);
        
        const queueImprovement = (parseFloat(queueOps) / parseFloat(syncOps)).toFixed(2);
        console.log(`\nQueue throughput improvement: ${queueImprovement}x`);
        console.log(`\nNote: The write queue is most beneficial when you don't need to wait`);
        console.log(`for each write to complete, allowing true fire-and-forget semantics.`);
        
    } catch (error) {
        console.error('Benchmark failed:', error);
    } finally {
        // Clean up
        fs.rmSync(dataDir, { recursive: true });
    }
}

main().catch(console.error);