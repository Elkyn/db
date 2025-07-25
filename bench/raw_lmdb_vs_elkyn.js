#!/usr/bin/env node

const { ElkynStore } = require('../nodejs-bindings');
const { open } = require('lmdb');
const fs = require('fs');

function benchmarkRawLMDB() {
  console.log('🔥 Raw LMDB Performance Test\n');
  
  const dbPath = './raw-lmdb-test';
  
  // Clean slate
  if (fs.existsSync(dbPath)) {
    fs.rmSync(dbPath, { recursive: true, force: true });
  }
  
  const db = open({
    path: dbPath,
    compression: false,
    mapSize: 100 * 1024 * 1024
  });
  
  const iterations = 1000;
  
  console.log('=== Raw LMDB Write Performance ===');
  const rawStart = Date.now();
  
  db.transactionSync(() => {
    for (let i = 0; i < iterations; i++) {
      // Store the same object structure as Elkyn but as single entry
      db.put(`/perf/${i}`, JSON.stringify({ data: 'test', id: i }));
    }
  });
  
  const rawElapsed = Date.now() - rawStart;
  const rawOpsPerSec = Math.round((iterations / rawElapsed) * 1000);
  
  console.log(`Raw LMDB: ${rawOpsPerSec} ops/sec (${iterations} iterations in ${rawElapsed}ms)`);
  
  console.log('\n=== Raw LMDB Decomposed Write Performance ===');
  const decomposedStart = Date.now();
  
  db.transactionSync(() => {
    for (let i = 0; i < iterations; i++) {
      // Store object as decomposed fields like Elkyn does
      db.put(`/decomp/${i}/data`, 'test');
      db.put(`/decomp/${i}/id`, String(i));
    }
  });
  
  const decomposedElapsed = Date.now() - decomposedStart;
  const decomposedOpsPerSec = Math.round((iterations / decomposedElapsed) * 1000);
  
  console.log(`Raw LMDB Decomposed: ${decomposedOpsPerSec} ops/sec (${iterations} iterations in ${decomposedElapsed}ms)`);
  
  db.close();
  
  return {
    raw: rawOpsPerSec,
    decomposed: decomposedOpsPerSec
  };
}

function benchmarkElkynZig() {
  console.log('\n🔥 Elkyn Zig Performance Test\n');
  
  const dbPath = './elkyn-zig-test';
  
  // Clean slate
  if (fs.existsSync(dbPath)) {
    fs.rmSync(dbPath, { recursive: true, force: true });
  }
  
  const store = new ElkynStore({ 
    mode: 'standalone', 
    dataDir: dbPath 
  });
  
  const iterations = 1000;
  
  console.log('=== Elkyn Zig Write Performance ===');
  const elkynStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    store.set(`/perf/${i}`, { data: 'test', id: i });
  }
  
  const elkynElapsed = Date.now() - elkynStart;
  const elkynOpsPerSec = Math.round((iterations / elkynElapsed) * 1000);
  
  console.log(`Elkyn Zig: ${elkynOpsPerSec} ops/sec (${iterations} iterations in ${elkynElapsed}ms)`);
  
  store.close();
  
  return {
    elkyn: elkynOpsPerSec
  };
}

function analyzeOverhead() {
  console.log('\n📊 Performance Analysis\n');
  
  const lmdbResults = benchmarkRawLMDB();
  const elkynResults = benchmarkElkynZig();
  
  console.log('='.repeat(60));
  console.log('PERFORMANCE COMPARISON');
  console.log('='.repeat(60));
  
  console.log(`\nRaw LMDB (single entry):     ${lmdbResults.raw.toLocaleString()} ops/sec`);
  console.log(`Raw LMDB (decomposed):       ${lmdbResults.decomposed.toLocaleString()} ops/sec`);
  console.log(`Elkyn Zig (with features):   ${elkynResults.elkyn.toLocaleString()} ops/sec`);
  
  const decompositionOverhead = lmdbResults.raw / lmdbResults.decomposed;
  const elkynOverhead = lmdbResults.decomposed / elkynResults.elkyn;
  const totalOverhead = lmdbResults.raw / elkynResults.elkyn;
  
  console.log('\n📈 Overhead Analysis:');
  console.log(`   Object decomposition overhead:    ${decompositionOverhead.toFixed(1)}x slower`);
  console.log(`   Elkyn features overhead:          ${elkynOverhead.toFixed(1)}x slower`);
  console.log(`   Total overhead vs raw LMDB:      ${totalOverhead.toFixed(1)}x slower`);
  
  console.log('\n🎯 Bottleneck Identification:');
  if (decompositionOverhead > elkynOverhead) {
    console.log('   ⚠️  Main bottleneck: Object decomposition (multiple LMDB puts)');
    console.log('   💡 Optimization target: Reduce number of LMDB operations');
  } else {
    console.log('   ⚠️  Main bottleneck: Elkyn features (MessagePack, events, etc.)');
    console.log('   💡 Optimization target: Streamline Zig processing');
  }
  
  console.log('\n📋 What each system does:');
  console.log('   Raw LMDB Single:');
  console.log('     • 1 LMDB put per object');
  console.log('     • JSON serialization');
  console.log('     • No field access possible');
  
  console.log('   Raw LMDB Decomposed:');
  console.log('     • 2 LMDB puts per object (data + id)');
  console.log('     • String serialization only');
  console.log('     • Field access possible');
  
  console.log('   Elkyn Zig:');
  console.log('     • 2 LMDB puts per object (data + id)');
  console.log('     • MessagePack serialization');
  console.log('     • JSON parsing (value_str -> Value)');
  console.log('     • Event emission');
  console.log('     • Path normalization');
  console.log('     • Memory management');
  
  return {
    lmdb: lmdbResults,
    elkyn: elkynResults,
    overheads: {
      decomposition: decompositionOverhead,
      elkyn: elkynOverhead,
      total: totalOverhead
    }
  };
}

const results = analyzeOverhead();

console.log('\n🔍 Detailed Bottleneck Analysis:');
console.log('\nPer-operation breakdown (estimated):');

const rawLMDBTime = 1000 / results.lmdb.raw; // ms per operation
const elkynTime = 1000 / results.elkyn.elkyn; // ms per operation

console.log(`   Raw LMDB operation:        ${rawLMDBTime.toFixed(3)}ms`);
console.log(`   Elkyn operation:           ${elkynTime.toFixed(3)}ms`);
console.log(`   Additional overhead:       ${(elkynTime - rawLMDBTime).toFixed(3)}ms per operation`);

console.log('\nOverhead comes from:');
console.log('   1. Multiple LMDB puts (decomposition)');
console.log('   2. MessagePack serialization vs JSON');
console.log('   3. JSON parsing (JavaScript -> Zig Value)');
console.log('   4. Event emission system');
console.log('   5. N-API bridge overhead');
console.log('   6. Memory allocations in Zig');

console.log('\n💡 Optimization Opportunities:');
console.log('   1. 🎯 Batch writes (reduce LMDB puts)');
console.log('   2. 🎯 Skip events when no listeners');
console.log('   3. 🎯 Pool allocations');
console.log('   4. 🎯 Faster serialization');
console.log('   5. 🎯 Reduce N-API calls');

console.log('\n❗ Trade-offs to consider:');
console.log('   • Simpler storage = faster but less features');
console.log('   • Field access requires decomposition');
console.log('   • Events require overhead');
console.log('   • Safety requires validation');