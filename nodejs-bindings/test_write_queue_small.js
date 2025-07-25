const { ElkynStore } = require('./index.js');
const fs = require('fs');
const path = require('path');

// Create test directory
const dataDir = path.join(__dirname, 'data_test_small');
if (fs.existsSync(dataDir)) {
    fs.rmSync(dataDir, { recursive: true });
}
fs.mkdirSync(dataDir);

async function test() {
    const db = new ElkynStore(dataDir);
    
    try {
        console.log('Testing small write queue...');
        
        // Enable write queue
        db.enableWriteQueue();
        console.log('Write queue enabled');
        
        // Write one item
        console.log('Writing one item...');
        const id = db.setAsync('/test/item1', { data: 'test-1' });
        console.log('Write ID:', id);
        
        // Wait for it
        console.log('Waiting for write...');
        await db.waitForWrite(id);
        console.log('Write completed!');
        
        // Verify
        const value = db.get('/test/item1');
        console.log('Retrieved value:', value);
        
    } catch (error) {
        console.error('Error:', error);
    } finally {
        db.close();
        fs.rmSync(dataDir, { recursive: true });
    }
}

test().catch(console.error);