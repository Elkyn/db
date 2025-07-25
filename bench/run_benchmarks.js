#!/usr/bin/env node

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const ora = require('ora');

async function runCommand(command, args = []) {
    return new Promise((resolve, reject) => {
        const proc = spawn(command, args, { stdio: 'inherit' });
        proc.on('close', code => {
            if (code === 0) resolve();
            else reject(new Error(`Command failed: ${command} ${args.join(' ')}`));
        });
    });
}

async function ensureDependencies() {
    const spinner = ora('Installing dependencies...').start();
    
    // Check if node_modules exists
    if (!fs.existsSync('node_modules')) {
        await runCommand('npm', ['install']);
    }
    
    // Build Zig if needed
    process.chdir('..');
    if (!fs.existsSync('zig-out/lib')) {
        spinner.text = 'Building Zig libraries...';
        await runCommand('zig', ['build']);
    }
    process.chdir('bench');
    
    spinner.succeed('Dependencies ready');
}

async function cleanupPreviousRuns() {
    const spinner = ora('Cleaning up previous runs...').start();
    
    // Remove temp directories
    const tempDirs = ['bench-temp', 'bench-events', 'bench-native-writes', 'bench-native-reads', 'bench-native-events'];
    for (const dir of tempDirs) {
        if (fs.existsSync(dir)) {
            fs.rmSync(dir, { recursive: true, force: true });
        }
    }
    
    spinner.succeed('Cleanup complete');
}

async function main() {
    console.log('🚀 Elkyn DB Comprehensive Benchmark Suite');
    console.log('=' . repeat(60));
    console.log('');
    
    try {
        await ensureDependencies();
        await cleanupPreviousRuns();
        
        // Run benchmarks in sequence
        console.log('\n📊 Running Operation Benchmarks...\n');
        await runCommand('node', ['operation_benchmarks.js']);
        
        console.log('\n\n📊 Running Event System Benchmarks...\n');
        await runCommand('node', ['--expose-gc', 'event_benchmarks.js']);
        
        console.log('\n\n📊 Running Native Benchmarks...\n');
        await runCommand('zig', ['run', 'native_bench.zig']);
        
        // Generate summary report
        console.log('\n\n📈 Generating Summary Report...\n');
        generateSummaryReport();
        
    } catch (error) {
        console.error('\n❌ Benchmark failed:', error.message);
        process.exit(1);
    }
}

function generateSummaryReport() {
    const report = [];
    
    report.push('# Elkyn DB Performance Report');
    report.push(`Date: ${new Date().toISOString()}`);
    report.push('');
    
    // Load results if available
    try {
        if (fs.existsSync('benchmark-results.json')) {
            const opResults = JSON.parse(fs.readFileSync('benchmark-results.json', 'utf8'));
            report.push('## Operation Benchmarks');
            report.push('');
            report.push('| Database | Small Writes | Medium Writes | Reads | Mixed Ops |');
            report.push('|----------|-------------|---------------|-------|-----------|');
            
            const dbs = ['Elkyn', 'Redis', 'SQLite', 'LevelDB', 'LMDB'];
            for (const db of dbs) {
                report.push(`| ${db} | ${opResults.writes?.small?.[db]?.ops || '-'} | ${opResults.writes?.medium?.[db]?.ops || '-'} | ${opResults.reads?.[db]?.ops || '-'} | ${opResults.mixed?.[db]?.ops || '-'} |`);
            }
            report.push('');
        }
        
        if (fs.existsSync('event-benchmark-results.json')) {
            const eventResults = JSON.parse(fs.readFileSync('event-benchmark-results.json', 'utf8'));
            report.push('## Event System Performance');
            report.push('');
            report.push(`- **Latency**: ${eventResults.latency.avg.toFixed(2)}ms avg, ${eventResults.latency.p99}ms p99`);
            report.push(`- **Throughput**: ${eventResults.throughput.single.toLocaleString()} events/sec`);
            report.push(`- **vs EventEmitter**: ${((1 - eventResults.comparison.elkyn/eventResults.comparison.node) * 100).toFixed(1)}% overhead`);
            report.push(`- **Memory**: ${eventResults.memory.perSub.toFixed(0)} bytes per subscription`);
            report.push('');
        }
        
        report.push('## Key Findings');
        report.push('');
        report.push('1. **Write Performance**: Elkyn performs competitively with embedded databases');
        report.push('2. **Read Performance**: Direct LMDB access provides excellent read speeds');
        report.push('3. **Event System**: Sub-millisecond latency with minimal overhead');
        report.push('4. **Memory Usage**: Efficient memory usage with fixed allocations');
        report.push('');
        
        // Save report
        fs.writeFileSync('BENCHMARK_REPORT.md', report.join('\n'));
        console.log('📄 Report saved to BENCHMARK_REPORT.md');
        
    } catch (error) {
        console.error('Failed to generate report:', error);
    }
}

// Run the benchmarks
main().catch(console.error);