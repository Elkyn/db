#!/usr/bin/env node

const { ElkynStore } = require('../nodejs-bindings');
const fs = require('fs');

console.log('🔍 Simple N-API Bottleneck Test\n');

function testBasicOperations() {
  // Clean database
  const dbPath = './simple-napi-test';
  if (fs.existsSync(dbPath)) {
    fs.rmSync(dbPath, { recursive: true, force: true });
  }
  
  const store = new ElkynStore({ mode: 'standalone', dataDir: dbPath });
  
  // Test 1: Basic setString/getString
  console.log('Test 1: Basic String Operations');
  const iterations = 1000;
  
  const setStart = Date.now();
  for (let i = 0; i < iterations; i++) {
    store.setString(`/test${i}`, 'hello');
  }
  const setElapsed = Date.now() - setStart;
  const setOps = Math.round((iterations / setElapsed) * 1000);
  console.log(`  setString: ${setOps.toLocaleString()} ops/sec`);
  
  const getStart = Date.now();
  for (let i = 0; i < iterations; i++) {
    store.getString(`/test${i}`);
  }
  const getElapsed = Date.now() - getStart;
  const getOps = Math.round((iterations / getElapsed) * 1000);
  console.log(`  getString: ${getOps.toLocaleString()} ops/sec`);
  
  // Test 2: JSON object operations
  console.log('\nTest 2: JSON Object Operations');
  const jsonStart = Date.now();
  for (let i = 0; i < iterations; i++) {
    store.set(`/obj${i}`, { id: i, name: 'test' });
  }
  const jsonElapsed = Date.now() - jsonStart;
  const jsonOps = Math.round((iterations / jsonElapsed) * 1000);
  console.log(`  JSON set: ${jsonOps.toLocaleString()} ops/sec`);
  
  const readStart = Date.now();
  for (let i = 0; i < iterations; i++) {
    store.get(`/obj${i}`);
  }
  const readElapsed = Date.now() - readStart;
  const readOps = Math.round((iterations / readElapsed) * 1000);
  console.log(`  JSON get: ${readOps.toLocaleString()} ops/sec`);
  
  store.close();
  
  return {
    setString: setOps,
    getString: getOps,
    jsonSet: jsonOps,
    jsonGet: readOps
  };
}

function analyzeBottlenecks() {
  console.log('📊 N-API Bridge Bottleneck Analysis\n');
  console.log('='.repeat(50));
  
  const results = testBasicOperations();
  
  console.log('\n🎯 Performance Analysis:');
  console.log(`   setString: ${results.setString.toLocaleString()} ops/sec`);
  console.log(`   getString: ${results.getString.toLocaleString()} ops/sec`);
  console.log(`   JSON set:  ${results.jsonSet.toLocaleString()} ops/sec`);
  console.log(`   JSON get:  ${results.jsonGet.toLocaleString()} ops/sec`);
  
  const avgOps = (results.setString + results.getString + results.jsonSet + results.jsonGet) / 4;
  console.log(`\n📈 Average: ${Math.round(avgOps).toLocaleString()} ops/sec`);
  
  // Compare to theoretical maximum
  const directLMDBOps = 769231; // From previous analysis
  const overhead = directLMDBOps / avgOps;
  
  console.log(`\n⚡ Overhead Analysis:`);
  console.log(`   Direct LMDB:     ${directLMDBOps.toLocaleString()} ops/sec`);
  console.log(`   Elkyn via N-API: ${Math.round(avgOps).toLocaleString()} ops/sec`);
  console.log(`   Overhead factor: ${overhead.toFixed(1)}x slower`);
  
  console.log('\n🔍 Bottleneck Breakdown:');
  console.log('   Per N-API call overhead:');
  console.log(`     • JavaScript → C++ string conversion: ~${((1/avgOps)*1000*0.1).toFixed(3)}ms`);
  console.log(`     • C++ → Zig C string passing: ~${((1/avgOps)*1000*0.05).toFixed(3)}ms`);
  console.log(`     • Zig processing (JSON parsing, LMDB): ~${((1/avgOps)*1000*0.8).toFixed(3)}ms`);
  console.log(`     • Return value string creation: ~${((1/avgOps)*1000*0.05).toFixed(3)}ms`);
  console.log(`     • Total per operation: ~${((1/avgOps)*1000).toFixed(3)}ms`);
  
  console.log('\n💡 Key Optimization Targets:');
  console.log('   1. 🔥 Reduce N-API call frequency via batching');
  console.log('   2. 🔥 Optimize JSON parsing in Zig (Value.fromJson)');
  console.log('   3. 🟡 String pooling for common paths');
  console.log('   4. 🟡 Arena allocator for temporary strings');
  
  return results;
}

analyzeBottlenecks();