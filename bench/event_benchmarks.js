const { ElkynStore } = require('@elkyn/store');
const EventEmitter = require('events');
const Table = require('cli-table3');
const ora = require('ora');

class EventBenchmark {
    constructor() {
        this.results = {};
    }
    
    async measureLatency() {
        console.log('\n⏱️  Event Latency Test');
        console.log('=' . repeat(50));
        
        const store = new ElkynStore({ mode: 'standalone', dataDir: './bench-events' });
        
        // Measure Elkyn event latency
        const latencies = [];
        let receivedCount = 0;
        
        const sub = store.watch('/latency/*').subscribe(event => {
            const latency = Date.now() - parseInt(event.path.split('/').pop());
            latencies.push(latency);
            receivedCount++;
        });
        
        // Send events
        const testCount = 1000;
        for (let i = 0; i < testCount; i++) {
            store.set(`/latency/${Date.now()}`, { index: i });
            // Small delay to avoid overwhelming
            if (i % 100 === 0) {
                await new Promise(resolve => setTimeout(resolve, 1));
            }
        }
        
        // Wait for all events
        const waitStart = Date.now();
        while (receivedCount < testCount && Date.now() - waitStart < 5000) {
            await new Promise(resolve => setTimeout(resolve, 10));
        }
        
        sub.unsubscribe();
        store.close();
        
        // Calculate stats
        latencies.sort((a, b) => a - b);
        const stats = {
            min: Math.min(...latencies),
            max: Math.max(...latencies),
            avg: latencies.reduce((a, b) => a + b, 0) / latencies.length,
            p50: latencies[Math.floor(latencies.length * 0.5)],
            p95: latencies[Math.floor(latencies.length * 0.95)],
            p99: latencies[Math.floor(latencies.length * 0.99)]
        };
        
        console.log(`  Received: ${receivedCount}/${testCount} events`);
        console.log(`  Latency (ms):`);
        console.log(`    Min: ${stats.min}`);
        console.log(`    Avg: ${stats.avg.toFixed(2)}`);
        console.log(`    P50: ${stats.p50}`);
        console.log(`    P95: ${stats.p95}`);
        console.log(`    P99: ${stats.p99}`);
        console.log(`    Max: ${stats.max}`);
        
        return stats;
    }
    
    async measureThroughput() {
        console.log('\n📈 Event Throughput Test');
        console.log('=' . repeat(50));
        
        const results = {};
        
        // Test 1: Single subscriber throughput
        {
            const store = new ElkynStore({ mode: 'standalone', dataDir: './bench-throughput' });
            let count = 0;
            
            const sub = store.watch('/*').subscribe(() => count++);
            
            const startTime = Date.now();
            const testDuration = 5000; // 5 seconds
            
            // Pump events as fast as possible
            while (Date.now() - startTime < testDuration) {
                for (let i = 0; i < 100; i++) {
                    store.set(`/item/${i}`, { value: i });
                }
            }
            
            // Wait a bit for events to propagate
            await new Promise(resolve => setTimeout(resolve, 100));
            
            const elapsed = Date.now() - startTime;
            const eventsPerSec = Math.round(count / (elapsed / 1000));
            
            console.log(`  Single subscriber: ${eventsPerSec.toLocaleString()} events/sec`);
            results.single = eventsPerSec;
            
            sub.unsubscribe();
            store.close();
        }
        
        // Test 2: Multiple subscribers
        {
            const store = new ElkynStore({ mode: 'standalone', dataDir: './bench-multi' });
            const counts = [0, 0, 0, 0, 0];
            const subs = [];
            
            // Create 5 subscribers
            for (let i = 0; i < 5; i++) {
                const idx = i;
                subs.push(store.watch('/*').subscribe(() => counts[idx]++));
            }
            
            const startTime = Date.now();
            const testDuration = 5000;
            
            while (Date.now() - startTime < testDuration) {
                for (let i = 0; i < 100; i++) {
                    store.set(`/item/${i}`, { value: i });
                }
            }
            
            await new Promise(resolve => setTimeout(resolve, 100));
            
            const elapsed = Date.now() - startTime;
            const totalEvents = counts.reduce((a, b) => a + b, 0);
            const eventsPerSec = Math.round(totalEvents / (elapsed / 1000) / 5); // Per subscriber
            
            console.log(`  5 subscribers: ${eventsPerSec.toLocaleString()} events/sec per subscriber`);
            results.multiple = eventsPerSec;
            
            subs.forEach(sub => sub.unsubscribe());
            store.close();
        }
        
        // Test 3: Filtered events
        {
            const store = new ElkynStore({ mode: 'standalone', dataDir: './bench-filtered' });
            let count = 0;
            
            const sub = store.watch('/important/*')
                .filter(e => e.type === 'change')
                .map(e => ({ path: e.path, timestamp: Date.now() }))
                .subscribe(() => count++);
            
            const startTime = Date.now();
            const testDuration = 5000;
            
            while (Date.now() - startTime < testDuration) {
                for (let i = 0; i < 50; i++) {
                    store.set(`/important/${i}`, { value: i });
                    store.set(`/other/${i}`, { value: i }); // Should be filtered out
                }
            }
            
            await new Promise(resolve => setTimeout(resolve, 100));
            
            const elapsed = Date.now() - startTime;
            const eventsPerSec = Math.round(count / (elapsed / 1000));
            
            console.log(`  Filtered (50%): ${eventsPerSec.toLocaleString()} events/sec`);
            results.filtered = eventsPerSec;
            
            sub.unsubscribe();
            store.close();
        }
        
        return results;
    }
    
    async compareWithNodeEventEmitter() {
        console.log('\n⚡ Elkyn vs Node.js EventEmitter');
        console.log('=' . repeat(50));
        
        const iterations = 1000000;
        
        // Test Node.js EventEmitter
        const emitter = new EventEmitter();
        let nodeCount = 0;
        
        emitter.on('test', () => nodeCount++);
        
        const nodeStart = Date.now();
        for (let i = 0; i < iterations; i++) {
            emitter.emit('test', { value: i });
        }
        const nodeTime = Date.now() - nodeStart;
        const nodeOps = Math.round(iterations / (nodeTime / 1000));
        
        console.log(`  Node EventEmitter: ${nodeOps.toLocaleString()} events/sec`);
        
        // Test Elkyn (in-memory, no persistence)
        const store = new ElkynStore({ mode: 'standalone', dataDir: './bench-memory' });
        let elkynCount = 0;
        
        const sub = store.watch('/test').subscribe(() => elkynCount++);
        
        const elkynStart = Date.now();
        for (let i = 0; i < iterations; i++) {
            store.set('/test', { value: i });
        }
        
        // Wait for events to propagate
        while (elkynCount < iterations && Date.now() - elkynStart < 10000) {
            await new Promise(resolve => setTimeout(resolve, 10));
        }
        
        const elkynTime = Date.now() - elkynStart;
        const elkynOps = Math.round(elkynCount / (elkynTime / 1000));
        
        console.log(`  Elkyn (w/ persistence): ${elkynOps.toLocaleString()} events/sec`);
        console.log(`  Overhead: ${((1 - elkynOps/nodeOps) * 100).toFixed(1)}%`);
        
        sub.unsubscribe();
        store.close();
        
        return { node: nodeOps, elkyn: elkynOps };
    }
    
    async measureMemoryOverhead() {
        console.log('\n💾 Memory Overhead Test');
        console.log('=' . repeat(50));
        
        const store = new ElkynStore({ mode: 'standalone', dataDir: './bench-mem' });
        const subscriptions = [];
        
        // Get baseline
        if (global.gc) global.gc();
        const baseline = process.memoryUsage();
        
        // Create many subscriptions
        const subCount = 1000;
        for (let i = 0; i < subCount; i++) {
            subscriptions.push(
                store.watch(`/path/${i}/*`).subscribe(() => {})
            );
        }
        
        // Measure with subscriptions
        if (global.gc) global.gc();
        const withSubs = process.memoryUsage();
        
        // Calculate overhead
        const overhead = {
            heap: (withSubs.heapUsed - baseline.heapUsed) / 1024 / 1024,
            external: (withSubs.external - baseline.external) / 1024 / 1024,
            perSub: (withSubs.heapUsed - baseline.heapUsed) / subCount
        };
        
        console.log(`  ${subCount} subscriptions:`);
        console.log(`    Heap overhead: ${overhead.heap.toFixed(2)} MB`);
        console.log(`    External overhead: ${overhead.external.toFixed(2)} MB`);
        console.log(`    Per subscription: ${overhead.perSub.toFixed(0)} bytes`);
        
        // Cleanup
        subscriptions.forEach(sub => sub.unsubscribe());
        store.close();
        
        return overhead;
    }
    
    async runAllBenchmarks() {
        const latency = await this.measureLatency();
        const throughput = await this.measureThroughput();
        const comparison = await this.compareWithNodeEventEmitter();
        const memory = await this.measureMemoryOverhead();
        
        // Summary table
        console.log('\n📊 Event System Performance Summary');
        console.log('=' . repeat(60));
        
        const table = new Table({
            head: ['Metric', 'Value', 'Notes'],
            colWidths: [25, 20, 25]
        });
        
        table.push(
            ['Latency (avg)', `${latency.avg.toFixed(2)} ms`, 'End-to-end'],
            ['Latency (p99)', `${latency.p99} ms`, '99th percentile'],
            ['Throughput (single)', `${throughput.single.toLocaleString()}/sec`, '1 subscriber'],
            ['Throughput (multi)', `${throughput.multiple.toLocaleString()}/sec`, '5 subscribers'],
            ['vs EventEmitter', `${((1 - comparison.elkyn/comparison.node) * 100).toFixed(1)}% overhead`, 'With persistence'],
            ['Memory/subscription', `${memory.perSub.toFixed(0)} bytes`, 'Heap usage']
        );
        
        console.log(table.toString());
        
        return {
            latency,
            throughput,
            comparison,
            memory
        };
    }
}

async function main() {
    console.log('🚀 Elkyn Event System Benchmarks');
    console.log('Testing: Latency, Throughput, Memory Usage\n');
    
    const benchmark = new EventBenchmark();
    
    try {
        const results = await benchmark.runAllBenchmarks();
        
        // Save results
        require('fs').writeFileSync(
            'event-benchmark-results.json',
            JSON.stringify(results, null, 2)
        );
        
        console.log('\n💾 Results saved to event-benchmark-results.json');
        
    } catch (error) {
        console.error('Benchmark failed:', error);
    }
}

// Run with: node --expose-gc event_benchmarks.js
main().catch(console.error);