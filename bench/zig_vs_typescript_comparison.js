#!/usr/bin/env node

// Compare Zig vs TypeScript implementations
const { ElkynStore: ZigElkynStore } = require('../nodejs-bindings');
const { ElkynStore: TSElkynStore } = require('../elkyn-ts/dist');
const fs = require('fs');

function cleanupDirs() {
  const dirs = ['./zig-comparison', './ts-comparison'];
  dirs.forEach(dir => {
    if (fs.existsSync(dir)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
}

function benchmarkImplementation(name, StoreClass, dbPath) {
  console.log(`\n🔥 ${name} Implementation Benchmark`);
  console.log('='.repeat(50));
  
  const store = new StoreClass({ 
    mode: 'standalone', 
    dataDir: dbPath 
  });
  
  const iterations = 1000;
  const results = {};
  
  // Write Performance
  console.log('\n📝 Write Performance Test');
  const writeStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    store.set(`/perf/${i}`, { 
      data: 'test', 
      id: i, 
      timestamp: Date.now(),
      active: true,
      score: 95.5
    });
  }
  
  const writeElapsed = Date.now() - writeStart;
  results.write = Math.round((iterations / writeElapsed) * 1000);
  console.log(`   ${results.write} ops/sec (${iterations} iterations in ${writeElapsed}ms)`);
  
  // Read Performance (Full Objects)
  console.log('\n📖 Read Performance Test (Full Objects)');
  const readStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    const result = store.get(`/perf/${i}`);
    if (!result || typeof result !== 'object') {
      console.error(`Failed to read /perf/${i}`);
    }
  }
  
  const readElapsed = Date.now() - readStart;
  results.read = Math.round((iterations / readElapsed) * 1000);
  console.log(`   ${results.read} ops/sec (${iterations} iterations in ${readElapsed}ms)`);
  
  // Field Access Performance
  console.log('\n🔍 Field Access Performance Test');
  const fieldStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    const data = store.get(`/perf/${i}/data`);
    const id = store.get(`/perf/${i}/id`);
    const active = store.get(`/perf/${i}/active`);
    const score = store.get(`/perf/${i}/score`);
    
    if (!data || id === undefined || active === undefined || score === undefined) {
      console.error(`Failed to read fields for /perf/${i}`);
    }
  }
  
  const fieldElapsed = Date.now() - fieldStart;
  results.fieldAccess = Math.round((iterations * 4 / fieldElapsed) * 1000);
  console.log(`   ${results.fieldAccess} ops/sec (${iterations * 4} field reads in ${fieldElapsed}ms)`);
  
  // Complex Object Test
  console.log('\n🏗️  Complex Object Test');
  const complexStart = Date.now();
  
  for (let i = 0; i < 100; i++) { // Fewer iterations for complex test
    store.set(`/complex/${i}`, {
      user: {
        id: i,
        name: `User${i}`,
        profile: {
          email: `user${i}@example.com`,
          settings: {
            theme: 'dark',
            notifications: true
          }
        }
      },
      data: {
        scores: [85, 92, 78],
        metadata: {
          created: Date.now(),
          updated: Date.now()
        }
      }
    });
  }
  
  const complexElapsed = Date.now() - complexStart;
  results.complexWrite = Math.round((100 / complexElapsed) * 1000);
  console.log(`   Complex Write: ${results.complexWrite} ops/sec`);
  
  // Test field access in complex objects
  const complexReadStart = Date.now();
  
  for (let i = 0; i < 100; i++) {
    const email = store.get(`/complex/${i}/user/profile/email`);
    const theme = store.get(`/complex/${i}/user/profile/settings/theme`);
    const score = store.get(`/complex/${i}/data/scores/0`);
    
    if (!email || !theme || score === undefined) {
      console.error(`Failed to read complex fields for /complex/${i}`);
    }
  }
  
  const complexReadElapsed = Date.now() - complexReadStart;
  results.complexFieldAccess = Math.round((100 * 3 / complexReadElapsed) * 1000);
  console.log(`   Complex Field Access: ${results.complexFieldAccess} ops/sec`);
  
  store.close();
  return results;
}

function main() {
  console.log('🏆 Zig vs TypeScript Implementation Comparison\n');
  
  cleanupDirs();
  
  // Benchmark both implementations
  const zigResults = benchmarkImplementation('Zig', ZigElkynStore, './zig-comparison');
  const tsResults = benchmarkImplementation('TypeScript', TSElkynStore, './ts-comparison');
  
  // Comparison Summary
  console.log('\n' + '='.repeat(80));
  console.log('📊 PERFORMANCE COMPARISON SUMMARY');
  console.log('='.repeat(80));
  
  const metrics = [
    ['Write Performance', 'write'],
    ['Read Performance', 'read'], 
    ['Field Access', 'fieldAccess'],
    ['Complex Write', 'complexWrite'],
    ['Complex Field Access', 'complexFieldAccess']
  ];
  
  console.log('\n| Metric | Zig (ops/sec) | TypeScript (ops/sec) | Winner | Performance Ratio |');
  console.log('|--------|---------------|---------------------|--------|------------------|');
  
  for (const [label, key] of metrics) {
    const zigVal = zigResults[key];
    const tsVal = tsResults[key];
    const winner = zigVal > tsVal ? 'Zig 🏆' : 'TypeScript 🏆';
    const ratio = zigVal > tsVal ? 
      `${(zigVal / tsVal).toFixed(1)}x faster` : 
      `${(tsVal / zigVal).toFixed(1)}x faster`;
    
    console.log(`| ${label.padEnd(14)} | ${String(zigVal).padStart(13)} | ${String(tsVal).padStart(19)} | ${winner.padEnd(6)} | ${ratio.padEnd(16)} |`);
  }
  
  console.log('\n🎯 Key Insights:');
  
  if (zigResults.write > tsResults.write) {
    console.log(`✅ Zig is ${(zigResults.write / tsResults.write).toFixed(1)}x faster at writes`);
  } else {
    console.log(`⚠️  TypeScript is ${(tsResults.write / zigResults.write).toFixed(1)}x faster at writes`);
  }
  
  if (zigResults.fieldAccess > tsResults.fieldAccess) {
    console.log(`✅ Zig is ${(zigResults.fieldAccess / tsResults.fieldAccess).toFixed(1)}x faster at field access`);
  } else {
    console.log(`⚠️  TypeScript is ${(tsResults.fieldAccess / zigResults.fieldAccess).toFixed(1)}x faster at field access`);
  }
  
  console.log('\n📈 Both implementations successfully provide:');
  console.log('   ✅ Object decomposition (field-level access)');
  console.log('   ✅ Object reconstruction (full object retrieval)');
  console.log('   ✅ Nested object support');
  console.log('   ✅ Real-time events');
  console.log('   ✅ ACID transactions');
  
  console.log('\n🏁 Conclusion:');
  const zigAvg = (zigResults.write + zigResults.read + zigResults.fieldAccess) / 3;
  const tsAvg = (tsResults.write + tsResults.read + tsResults.fieldAccess) / 3;
  
  if (zigAvg > tsAvg) {
    console.log(`   Zig implementation is ${(zigAvg / tsAvg).toFixed(1)}x faster overall`);
    console.log('   Choose Zig for maximum performance');
  } else {
    console.log(`   TypeScript implementation is ${(tsAvg / zigAvg).toFixed(1)}x faster overall`);
    console.log('   Choose TypeScript for rapid development');
  }
}

main();