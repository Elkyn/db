const { ElkynStore } = require('@elkyn/store');
const Database = require('better-sqlite3');
const { Level } = require('level');
const { open } = require('lmdb');

async function benchmark() {
    console.log('🚀 Quick Performance Comparison\n');
    
    // Setup databases
    const elkyn = new ElkynStore({ mode: 'standalone', dataDir: './bench-elkyn' });
    const sqlite = new Database('./bench.db');
    sqlite.exec('CREATE TABLE IF NOT EXISTS data (key TEXT PRIMARY KEY, value TEXT)');
    const level = new Level('./bench-level');
    const lmdb = open({ path: './bench-lmdb' });
    
    const iterations = 10000;
    const testData = { name: 'Test User', age: 30, active: true };
    
    console.log(`Running ${iterations} operations...\n`);
    
    // Write benchmark
    console.log('📝 Write Performance:');
    
    // Elkyn
    let start = Date.now();
    for (let i = 0; i < iterations; i++) {
        elkyn.set(`/user/${i}`, testData);
    }
    let elkynWriteTime = Date.now() - start;
    console.log(`  Elkyn: ${Math.round(iterations / (elkynWriteTime / 1000))} ops/sec`);
    
    // SQLite
    const stmt = sqlite.prepare('INSERT OR REPLACE INTO data VALUES (?, ?)');
    start = Date.now();
    for (let i = 0; i < iterations; i++) {
        stmt.run(`user_${i}`, JSON.stringify(testData));
    }
    let sqliteWriteTime = Date.now() - start;
    console.log(`  SQLite: ${Math.round(iterations / (sqliteWriteTime / 1000))} ops/sec`);
    
    // LevelDB
    start = Date.now();
    for (let i = 0; i < iterations; i++) {
        await level.put(`user_${i}`, JSON.stringify(testData));
    }
    let levelWriteTime = Date.now() - start;
    console.log(`  LevelDB: ${Math.round(iterations / (levelWriteTime / 1000))} ops/sec`);
    
    // LMDB
    start = Date.now();
    for (let i = 0; i < iterations; i++) {
        lmdb.put(`user_${i}`, testData);
    }
    let lmdbWriteTime = Date.now() - start;
    console.log(`  LMDB: ${Math.round(iterations / (lmdbWriteTime / 1000))} ops/sec`);
    
    // Read benchmark
    console.log('\n📖 Read Performance:');
    
    // Elkyn
    start = Date.now();
    for (let i = 0; i < iterations; i++) {
        elkyn.get(`/user/${i % 1000}`);
    }
    let elkynReadTime = Date.now() - start;
    console.log(`  Elkyn: ${Math.round(iterations / (elkynReadTime / 1000))} ops/sec`);
    
    // SQLite
    const readStmt = sqlite.prepare('SELECT value FROM data WHERE key = ?');
    start = Date.now();
    for (let i = 0; i < iterations; i++) {
        readStmt.get(`user_${i % 1000}`);
    }
    let sqliteReadTime = Date.now() - start;
    console.log(`  SQLite: ${Math.round(iterations / (sqliteReadTime / 1000))} ops/sec`);
    
    // LevelDB
    start = Date.now();
    for (let i = 0; i < iterations; i++) {
        try {
            await level.get(`user_${i % 1000}`);
        } catch (e) {}
    }
    let levelReadTime = Date.now() - start;
    console.log(`  LevelDB: ${Math.round(iterations / (levelReadTime / 1000))} ops/sec`);
    
    // LMDB
    start = Date.now();
    for (let i = 0; i < iterations; i++) {
        lmdb.get(`user_${i % 1000}`);
    }
    let lmdbReadTime = Date.now() - start;
    console.log(`  LMDB: ${Math.round(iterations / (lmdbReadTime / 1000))} ops/sec`);
    
    // Event benchmark (Elkyn only)
    console.log('\n⚡ Event System (Elkyn only):');
    let eventCount = 0;
    const sub = elkyn.watch('/*').subscribe(() => eventCount++);
    
    start = Date.now();
    for (let i = 0; i < 1000; i++) {
        elkyn.set(`/event/${i}`, { event: i });
    }
    
    // Wait for events
    await new Promise(resolve => setTimeout(resolve, 100));
    let eventTime = Date.now() - start;
    console.log(`  Events delivered: ${eventCount}`);
    console.log(`  Throughput: ${Math.round(eventCount / (eventTime / 1000))} events/sec`);
    
    // Cleanup
    sub.unsubscribe();
    elkyn.close();
    sqlite.close();
    await level.close();
    lmdb.close();
    
    console.log('\n✅ Benchmark complete!');
}

benchmark().catch(console.error);