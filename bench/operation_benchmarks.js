const Benchmark = require('benchmark');
const Table = require('cli-table3');
const ora = require('ora');
const fs = require('fs');
const path = require('path');

// Import databases
const { ElkynStore } = require('@elkyn/store');
const Redis = require('redis');
const Database = require('better-sqlite3');
const { Level } = require('level');
const { open } = require('lmdb');

// Test data
const TEST_DATA = {
    small: { name: 'John', age: 30 },
    medium: { 
        name: 'John Doe', 
        age: 30, 
        email: 'john@example.com',
        address: '123 Main St, City, Country',
        metadata: { created: Date.now(), tags: ['user', 'active'] }
    },
    large: {
        name: 'John Doe',
        description: 'x'.repeat(1000),
        data: Array(100).fill(0).map((_, i) => ({
            id: i,
            value: Math.random(),
            text: 'Lorem ipsum dolor sit amet'
        }))
    }
};

class BenchmarkRunner {
    constructor() {
        this.results = [];
        this.tempDir = './bench-temp';
        
        // Create temp directory
        if (!fs.existsSync(this.tempDir)) {
            fs.mkdirSync(this.tempDir, { recursive: true });
        }
    }
    
    async setup() {
        const spinner = ora('Setting up databases...').start();
        
        // Setup Elkyn
        this.elkyn = new ElkynStore({ 
            mode: 'standalone', 
            dataDir: path.join(this.tempDir, 'elkyn') 
        });
        
        // Setup Redis
        this.redis = Redis.createClient();
        await this.redis.connect();
        await this.redis.flushAll();
        
        // Setup SQLite
        this.sqlite = new Database(path.join(this.tempDir, 'bench.db'));
        this.sqlite.exec(`
            CREATE TABLE IF NOT EXISTS data (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        `);
        
        // Setup LevelDB
        this.level = new Level(path.join(this.tempDir, 'leveldb'));
        
        // Setup LMDB
        this.lmdb = open({
            path: path.join(this.tempDir, 'lmdb'),
            compression: false
        });
        
        spinner.succeed('Databases ready');
    }
    
    async cleanup() {
        await this.redis.quit();
        this.elkyn.close();
        this.sqlite.close();
        await this.level.close();
        this.lmdb.close();
    }
    
    runBenchmark(name, tests) {
        return new Promise((resolve) => {
            const suite = new Benchmark.Suite(name);
            const results = {};
            
            Object.entries(tests).forEach(([testName, fn]) => {
                suite.add(testName, fn);
            });
            
            suite
                .on('cycle', (event) => {
                    console.log(`  ${String(event.target)}`);
                    results[event.target.name] = {
                        ops: Math.round(event.target.hz),
                        rme: event.target.stats.rme.toFixed(2)
                    };
                })
                .on('complete', function() {
                    const fastest = this.filter('fastest').map('name');
                    console.log(`  Fastest: ${fastest.join(', ')}\n`);
                    resolve(results);
                })
                .run({ async: true });
        });
    }
    
    async benchmarkWrites() {
        console.log('\n📝 Write Performance (operations/second)');
        console.log('=' . repeat(50));
        
        const results = {};
        
        // Small payload writes
        console.log('\nSmall payload (50 bytes):');
        results.small = await this.runBenchmark('Small Writes', {
            'Elkyn': () => {
                this.elkyn.set(`/bench/${Date.now()}`, TEST_DATA.small);
            },
            'Redis': async () => {
                await this.redis.set(`bench:${Date.now()}`, JSON.stringify(TEST_DATA.small));
            },
            'SQLite': () => {
                const stmt = this.sqlite.prepare('INSERT OR REPLACE INTO data VALUES (?, ?)');
                stmt.run(`bench_${Date.now()}`, JSON.stringify(TEST_DATA.small));
            },
            'LevelDB': async () => {
                await this.level.put(`bench_${Date.now()}`, JSON.stringify(TEST_DATA.small));
            },
            'LMDB': () => {
                this.lmdb.put(`bench_${Date.now()}`, TEST_DATA.small);
            }
        });
        
        // Medium payload writes
        console.log('\nMedium payload (200 bytes):');
        results.medium = await this.runBenchmark('Medium Writes', {
            'Elkyn': () => {
                this.elkyn.set(`/bench/${Date.now()}`, TEST_DATA.medium);
            },
            'Redis': async () => {
                await this.redis.set(`bench:${Date.now()}`, JSON.stringify(TEST_DATA.medium));
            },
            'SQLite': () => {
                const stmt = this.sqlite.prepare('INSERT OR REPLACE INTO data VALUES (?, ?)');
                stmt.run(`bench_${Date.now()}`, JSON.stringify(TEST_DATA.medium));
            },
            'LevelDB': async () => {
                await this.level.put(`bench_${Date.now()}`, JSON.stringify(TEST_DATA.medium));
            },
            'LMDB': () => {
                this.lmdb.put(`bench_${Date.now()}`, TEST_DATA.medium);
            }
        });
        
        return results;
    }
    
    async benchmarkReads() {
        console.log('\n📖 Read Performance (operations/second)');
        console.log('=' . repeat(50));
        
        // Pre-populate data
        const keys = [];
        for (let i = 0; i < 1000; i++) {
            const key = `read_test_${i}`;
            keys.push(key);
            
            this.elkyn.set(`/${key}`, TEST_DATA.medium);
            await this.redis.set(key, JSON.stringify(TEST_DATA.medium));
            this.sqlite.prepare('INSERT OR REPLACE INTO data VALUES (?, ?)').run(key, JSON.stringify(TEST_DATA.medium));
            await this.level.put(key, JSON.stringify(TEST_DATA.medium));
            this.lmdb.put(key, TEST_DATA.medium);
        }
        
        let index = 0;
        const getNextKey = () => keys[index++ % keys.length];
        
        const results = await this.runBenchmark('Reads', {
            'Elkyn': () => {
                this.elkyn.get(`/${getNextKey()}`);
            },
            'Redis': async () => {
                await this.redis.get(getNextKey());
            },
            'SQLite': () => {
                const stmt = this.sqlite.prepare('SELECT value FROM data WHERE key = ?');
                stmt.get(getNextKey());
            },
            'LevelDB': async () => {
                await this.level.get(getNextKey());
            },
            'LMDB': () => {
                this.lmdb.get(getNextKey());
            }
        });
        
        return results;
    }
    
    async benchmarkMixedOps() {
        console.log('\n🔄 Mixed Operations (80% reads, 20% writes)');
        console.log('=' . repeat(50));
        
        let counter = 0;
        
        const results = await this.runBenchmark('Mixed Ops', {
            'Elkyn': () => {
                if (counter++ % 5 === 0) {
                    this.elkyn.set(`/mixed/${Date.now()}`, TEST_DATA.small);
                } else {
                    this.elkyn.get('/mixed/test');
                }
            },
            'Redis': async () => {
                if (counter++ % 5 === 0) {
                    await this.redis.set(`mixed:${Date.now()}`, JSON.stringify(TEST_DATA.small));
                } else {
                    await this.redis.get('mixed:test');
                }
            },
            'SQLite': () => {
                if (counter++ % 5 === 0) {
                    const stmt = this.sqlite.prepare('INSERT OR REPLACE INTO data VALUES (?, ?)');
                    stmt.run(`mixed_${Date.now()}`, JSON.stringify(TEST_DATA.small));
                } else {
                    const stmt = this.sqlite.prepare('SELECT value FROM data WHERE key = ?');
                    stmt.get('mixed_test');
                }
            },
            'LevelDB': async () => {
                if (counter++ % 5 === 0) {
                    await this.level.put(`mixed_${Date.now()}`, JSON.stringify(TEST_DATA.small));
                } else {
                    try { await this.level.get('mixed_test'); } catch {}
                }
            },
            'LMDB': () => {
                if (counter++ % 5 === 0) {
                    this.lmdb.put(`mixed_${Date.now()}`, TEST_DATA.small);
                } else {
                    this.lmdb.get('mixed_test');
                }
            }
        });
        
        return results;
    }
    
    displayResults(allResults) {
        console.log('\n📊 Summary');
        console.log('=' . repeat(80));
        
        const table = new Table({
            head: ['Database', 'Small Writes', 'Medium Writes', 'Reads', 'Mixed Ops'],
            colWidths: [15, 15, 15, 15, 15]
        });
        
        const databases = ['Elkyn', 'Redis', 'SQLite', 'LevelDB', 'LMDB'];
        
        databases.forEach(db => {
            table.push([
                db,
                allResults.writes?.small?.[db]?.ops || '-',
                allResults.writes?.medium?.[db]?.ops || '-',
                allResults.reads?.[db]?.ops || '-',
                allResults.mixed?.[db]?.ops || '-'
            ]);
        });
        
        console.log(table.toString());
    }
}

async function main() {
    console.log('🚀 Elkyn DB Performance Benchmarks');
    console.log('Comparing: Elkyn, Redis, SQLite, LevelDB, LMDB\n');
    
    const runner = new BenchmarkRunner();
    
    try {
        await runner.setup();
        
        const results = {
            writes: await runner.benchmarkWrites(),
            reads: await runner.benchmarkReads(),
            mixed: await runner.benchmarkMixedOps()
        };
        
        runner.displayResults(results);
        
        // Save results
        fs.writeFileSync(
            'benchmark-results.json',
            JSON.stringify(results, null, 2)
        );
        console.log('\n💾 Results saved to benchmark-results.json');
        
    } catch (error) {
        console.error('Benchmark failed:', error);
    } finally {
        await runner.cleanup();
    }
}

main().catch(console.error);