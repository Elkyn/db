const { ElkynStore } = require('./index.js');
const msgpack = require('msgpack5')();
const fs = require('fs');
const path = require('path');

// Create test directory
const dataDir = path.join(__dirname, 'data_test_write_queue');
if (fs.existsSync(dataDir)) {
    fs.rmSync(dataDir, { recursive: true });
}
fs.mkdirSync(dataDir);

async function testWriteQueue() {
    const db = new ElkynStore(dataDir);
    
    try {
        console.log('Testing write queue functionality...\n');
        
        // Enable write queue
        console.log('Enabling write queue...');
        db.enableWriteQueue();
        console.log('Write queue enabled!\n');
        
        // Test async writes
        console.log('Testing async writes...');
        const startTime = Date.now();
        const writeIds = [];
        
        // Queue multiple writes
        for (let i = 0; i < 100; i++) {
            const value = { index: i, data: `test-${i}` };
            const id = db.setAsync(`/test/item${i}`, value);
            writeIds.push(id);
        }
        
        const queueTime = Date.now() - startTime;
        console.log(`Queued 100 writes in ${queueTime}ms`);
        
        // Wait for a few writes
        console.log('\nWaiting for writes to complete...');
        for (let i = 0; i < 5; i++) {
            await db.waitForWrite(writeIds[i]);
        }
        
        // Verify some writes
        console.log('\nVerifying writes...');
        for (let i = 0; i < 5; i++) {
            const value = db.get(`/test/item${i}`);
            console.log(`  item${i}:`, value);
        }
        
        // Test async deletes
        console.log('\nTesting async deletes...');
        const deleteIds = [];
        for (let i = 0; i < 10; i++) {
            const id = db.deleteAsync(`/test/item${i}`);
            deleteIds.push(id);
        }
        
        // Wait for deletes
        for (const id of deleteIds) {
            await db.waitForWrite(id);
        }
        
        // Verify deletes
        console.log('Verifying deletes...');
        for (let i = 0; i < 10; i++) {
            const value = db.get(`/test/item${i}`);
            console.log(`  item${i}: ${value ? 'exists' : 'deleted'}`);
        }
        
        console.log('\nWrite queue test completed successfully!');
        
    } catch (error) {
        console.error('Error during test:', error);
    } finally {
        db.close();
        // Clean up
        fs.rmSync(dataDir, { recursive: true });
    }
}

testWriteQueue().catch(console.error);