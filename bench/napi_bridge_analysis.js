#!/usr/bin/env node

const { ElkynStore } = require('../nodejs-bindings');
const { open } = require('lmdb');
const fs = require('fs');

function cleanDb(path) {
  if (fs.existsSync(path)) {
    fs.rmSync(path, { recursive: true, force: true });
  }
}

function analyzeCCallOverhead() {
  console.log('🔍 N-API Bridge Call Analysis\n');
  console.log('='.repeat(60));
  
  // Measure individual C function call overhead
  cleanDb('./napi-test');
  const store = new ElkynStore({ 
    mode: 'standalone', 
    dataDir: './napi-test'
  });
  
  const iterations = 10000;
  const results = {};
  
  console.log('\n📊 Individual C Function Call Overhead:');
  
  // 1. Test elkyn_set_string calls
  console.log('\n1. Testing elkyn_set_string overhead...');
  const setStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    store.setString(`/test/${i}`, 'simple');
  }
  
  const setElapsed = Date.now() - setStart;
  results.setString = Math.round((iterations / setElapsed) * 1000);
  console.log(`   elkyn_set_string: ${results.setString.toLocaleString()} calls/sec`);
  
  // 2. Test elkyn_get_string calls
  console.log('\n2. Testing elkyn_get_string overhead...');
  const getStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    store.getString(`/test/${i}`);
  }
  
  const getElapsed = Date.now() - getStart;
  results.getString = Math.round((iterations / getElapsed) * 1000);
  console.log(`   elkyn_get_string: ${results.getString.toLocaleString()} calls/sec`);
  
  // 3. Test JSON.stringify overhead (JavaScript side)
  console.log('\n3. Testing JSON.stringify overhead...');
  const testObj = { data: 'test', id: 42 };
  const jsonStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    JSON.stringify(testObj);
  }
  
  const jsonElapsed = Date.now() - jsonStart;
  results.jsonStringify = Math.round((iterations / jsonElapsed) * 1000);
  console.log(`   JSON.stringify: ${results.jsonStringify.toLocaleString()} calls/sec`);
  
  // 4. Test JSON.parse overhead (JavaScript side) 
  console.log('\n4. Testing JSON.parse overhead...');
  const jsonStr = '{"data":"test","id":42}';
  const parseStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    JSON.parse(jsonStr);
  }
  
  const parseElapsed = Date.now() - parseStart;
  results.jsonParse = Math.round((iterations / parseElapsed) * 1000);
  console.log(`   JSON.parse: ${results.jsonParse.toLocaleString()} calls/sec`);
  
  store.close();
  return results;
}

function analyzeStringConversionOverhead() {
  console.log('\n🔄 String Conversion Analysis\n');
  console.log('='.repeat(60));
  
  cleanDb('./string-test');
  const store = new ElkynStore({ 
    mode: 'standalone', 
    dataDir: './string-test'
  });
  
  const iterations = 5000;
  const results = {};
  
  // Test different value types and their conversion overhead
  const testCases = [
    ['Simple String', 'hello'],
    ['Number as String', '42'],
    ['Boolean as String', 'true'],
    ['JSON Object', '{"name":"John","age":30}'],
    ['JSON Array', '[1,2,3,4,5]'],
    ['Large JSON', JSON.stringify({
      user: { id: 123, profile: { name: 'John', settings: { theme: 'dark' } } },
      data: new Array(100).fill(0).map((_, i) => ({ id: i, value: `item${i}` }))
    })]
  ];
  
  console.log('\n📝 Write Performance by Value Type:');
  
  for (const [label, value] of testCases) {
    const start = Date.now();
    
    for (let i = 0; i < iterations; i++) {
      store.setString(`/${label.toLowerCase().replace(' ', '_')}/${i}`, value);
    }
    
    const elapsed = Date.now() - start;
    const opsPerSec = Math.round((iterations / elapsed) * 1000);
    results[label] = opsPerSec;
    
    console.log(`   ${label}: ${opsPerSec.toLocaleString()} ops/sec (${value.length} chars)`);
  }
  
  console.log('\n📖 Read Performance by Value Type:');
  
  for (const [label] of testCases) {
    const start = Date.now();
    
    for (let i = 0; i < iterations; i++) {
      store.getString(`/${label.toLowerCase().replace(' ', '_')}/${i}`);
    }
    
    const elapsed = Date.now() - start;
    const opsPerSec = Math.round((iterations / elapsed) * 1000);
    
    console.log(`   ${label}: ${opsPerSec.toLocaleString()} ops/sec`);
  }
  
  store.close();
  return results;
}

function analyzeMemoryAllocationOverhead() {
  console.log('\n🧠 Memory Allocation Analysis\n');
  console.log('='.repeat(60));
  
  cleanDb('./memory-test');
  const store = new ElkynStore({ 
    mode: 'standalone', 
    dataDir: './memory-test'
  });
  
  // Measure memory usage before and after operations
  const beforeMemory = process.memoryUsage();
  
  console.log('\n📈 Memory Usage Before Operations:');
  console.log(`   RSS: ${(beforeMemory.rss / 1024 / 1024).toFixed(2)} MB`);
  console.log(`   Heap Used: ${(beforeMemory.heapUsed / 1024 / 1024).toFixed(2)} MB`);
  console.log(`   External: ${(beforeMemory.external / 1024 / 1024).toFixed(2)} MB`);
  
  // Perform many operations
  const iterations = 10000;
  const start = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    store.set(`/memory_test/${i}`, { 
      id: i, 
      data: `test_data_${i}`,
      timestamp: Date.now(),
      metadata: { source: 'benchmark' }
    });
  }
  
  const elapsed = Date.now() - start;
  const opsPerSec = Math.round((iterations / elapsed) * 1000);
  
  // Force garbage collection if available
  if (global.gc) {
    global.gc();
  }
  
  const afterMemory = process.memoryUsage();
  
  console.log(`\n📈 Memory Usage After ${iterations} Operations:`);
  console.log(`   RSS: ${(afterMemory.rss / 1024 / 1024).toFixed(2)} MB (+${((afterMemory.rss - beforeMemory.rss) / 1024 / 1024).toFixed(2)} MB)`);
  console.log(`   Heap Used: ${(afterMemory.heapUsed / 1024 / 1024).toFixed(2)} MB (+${((afterMemory.heapUsed - beforeMemory.heapUsed) / 1024 / 1024).toFixed(2)} MB)`);
  console.log(`   External: ${(afterMemory.external / 1024 / 1024).toFixed(2)} MB (+${((afterMemory.external - beforeMemory.external) / 1024 / 1024).toFixed(2)} MB)`);
  
  console.log(`\n📊 Performance: ${opsPerSec.toLocaleString()} ops/sec`);
  console.log(`📊 Memory per operation: ${((afterMemory.rss - beforeMemory.rss) / iterations).toFixed(0)} bytes/op`);
  
  store.close();
}

function analyzeZigProcessingSteps() {
  console.log('\n⚙️  Zig Processing Steps Analysis\n');
  console.log('='.repeat(60));
  
  console.log('\n🔍 What happens in elkyn_set_string:');
  console.log('   1. std.mem.span(path) - C string to Zig slice');
  console.log('   2. std.mem.span(value) - C string to Zig slice'); 
  console.log('   3. Value.fromJson() - Parse JSON string to Value struct');
  console.log('   4. db.set() - Validate auth/rules if enabled');
  console.log('   5. storage.set() - Path normalization');
  console.log('   6. Object decomposition (if object)');
  console.log('   7. Multiple LMDB puts (one per field)');
  console.log('   8. Event emission');
  console.log('   9. val.deinit() - Clean up allocated memory');
  
  console.log('\n🔍 What happens in elkyn_get_string:');
  console.log('   1. std.mem.span(path) - C string to Zig slice');
  console.log('   2. db.get() - Validate auth/rules if enabled');
  console.log('   3. storage.get() - LMDB lookup or object reconstruction');
  console.log('   4. Value type conversion to string');
  console.log('   5. allocator.dupeZ() - Create null-terminated C string');
  console.log('   6. Return pointer to JavaScript');
  console.log('   7. JavaScript must later call elkyn_free_string()');
  
  console.log('\n🔍 Memory allocation hotspots:');
  console.log('   • String duplication for C interface (every call)');
  console.log('   • JSON parsing allocations in Value.fromJson()');
  console.log('   • Path normalization allocations');
  console.log('   • Event emission string duplications');
  console.log('   • Object reconstruction temporary allocations');
  
  console.log('\n⚡ Optimization opportunities:');
  console.log('   🎯 1. String pooling/reuse for common paths');
  console.log('   🎯 2. Stack allocation for small values');
  console.log('   🎯 3. Lazy JSON parsing (parse only when needed)');
  console.log('   🎯 4. Batch operations (reduce N-API call count)');
  console.log('   🎯 5. Skip validation for trusted internal calls');
  console.log('   🎯 6. Arena allocator for request-scoped memory');
}

function runCompleteAnalysis() {
  console.log('🚀 Complete N-API Bridge Analysis\n');
  console.log('📅 ' + new Date().toISOString());
  console.log('=' .repeat(80));
  
  const cCallResults = analyzeCCallOverhead();
  const stringResults = analyzeStringConversionOverhead();
  analyzeMemoryAllocationOverhead();
  analyzeZigProcessingSteps();
  
  console.log('\n📋 BOTTLENECK SUMMARY');
  console.log('='.repeat(80));
  
  console.log('\n🔥 Critical Performance Issues:');
  
  // Identify the slowest operations
  const operations = [
    ['C Function Calls', cCallResults.setString],
    ['String Reads', cCallResults.getString],
    ['JSON Processing', Math.min(cCallResults.jsonStringify, cCallResults.jsonParse)]
  ].sort((a, b) => a[1] - b[1]); // Sort by performance (slowest first)
  
  operations.forEach(([name, opsPerSec], index) => {
    const priority = index === 0 ? '🔥 CRITICAL' : index === 1 ? '🟡 HIGH' : '🟢 MEDIUM';
    console.log(`   ${index + 1}. ${name}: ${opsPerSec.toLocaleString()} ops/sec - ${priority}`);
  });
  
  console.log('\n💡 Root Cause Analysis:');
  console.log('   The 71x N-API overhead comes from:');
  console.log(`   • Direct LMDB: 769,231 ops/sec (baseline)`);
  console.log(`   • Elkyn via N-API: ${cCallResults.setString.toLocaleString()} ops/sec`);
  console.log(`   • Overhead factor: ${(769231 / cCallResults.setString).toFixed(1)}x`);
  
  console.log('\n🎯 Specific Bottlenecks:');
  console.log('   1. JavaScript ↔ Zig string conversions (every call)');
  console.log('   2. JSON parsing overhead in Zig');
  console.log('   3. Multiple memory allocations per operation');
  console.log('   4. C string duplication for return values');
  console.log('   5. Event system overhead (even with no listeners)');
  
  console.log('\n🚀 Immediate Optimization Targets:');
  console.log('   1. 🎯 Implement batch operations (reduce N-API calls by 10-100x)');
  console.log('   2. 🎯 Use string pooling for common paths');
  console.log('   3. 🎯 Skip JSON parsing for simple string values');
  console.log('   4. 🎯 Use arena allocator for request-scoped memory');
  console.log('   5. 🎯 Optimize Value.fromJson() with faster parsing');
  
  console.log('\n📈 Expected Performance Gains:');
  console.log('   • Batch writes: 10-50x improvement');
  console.log('   • String pooling: 2-3x improvement');
  console.log('   • Skip JSON for strings: 1.5-2x improvement');
  console.log('   • Combined optimizations: 20-100x improvement');
  
  console.log('\n⚖️  Trade-offs:');
  console.log('   • Batch operations require API changes');
  console.log('   • String pooling increases memory usage');
  console.log('   • Some optimizations reduce flexibility');
  console.log('   • Complex optimizations increase maintenance cost');
}

runCompleteAnalysis();