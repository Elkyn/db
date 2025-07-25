#!/usr/bin/env node

const { ElkynStore } = require('../nodejs-bindings');
const { open } = require('lmdb');
const fs = require('fs');

function cleanDb(path) {
  if (fs.existsSync(path)) {
    fs.rmSync(path, { recursive: true, force: true });
  }
}

function testMessagePackOverhead() {
  console.log('🔥 MessagePack vs JSON Serialization Test\n');
  
  const iterations = 10000;
  const testData = { data: 'test', id: 42, active: true, score: 95.5 };
  
  // JSON serialization (what raw LMDB uses)
  console.log('Testing JSON serialization...');
  const jsonStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    JSON.stringify(testData);
  }
  
  const jsonElapsed = Date.now() - jsonStart;
  const jsonOpsPerSec = Math.round((iterations / jsonElapsed) * 1000);
  
  console.log(`JSON: ${jsonOpsPerSec.toLocaleString()} ops/sec`);
  
  // MessagePack via LMDB (what Elkyn uses internally)
  cleanDb('./msgpack-test');
  const db = open({ path: './msgpack-test' });
  
  console.log('Testing LMDB built-in serialization...');
  const msgpackStart = Date.now();
  
  db.transactionSync(() => {
    for (let i = 0; i < iterations; i++) {
      db.put(`test${i}`, testData); // LMDB handles serialization
    }
  });
  
  const msgpackElapsed = Date.now() - msgpackStart;
  const msgpackOpsPerSec = Math.round((iterations / msgpackElapsed) * 1000);
  
  console.log(`LMDB Serialization: ${msgpackOpsPerSec.toLocaleString()} ops/sec`);
  
  db.close();
  
  return {
    json: jsonOpsPerSec,
    msgpack: msgpackOpsPerSec
  };
}

function testEventOverhead() {
  console.log('\n🔥 Event System Overhead Test\n');
  
  const iterations = 1000;
  
  // Test with events disabled (if possible)
  cleanDb('./no-events-test');
  const storeNoEvents = new ElkynStore({ 
    mode: 'standalone', 
    dataDir: './no-events-test'
  });
  
  console.log('Testing writes with no event listeners...');
  const noEventsStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    storeNoEvents.set(`/test/${i}`, { data: 'test', id: i });
  }
  
  const noEventsElapsed = Date.now() - noEventsStart;
  const noEventsOpsPerSec = Math.round((iterations / noEventsElapsed) * 1000);
  
  console.log(`No Events: ${noEventsOpsPerSec.toLocaleString()} ops/sec`);
  
  storeNoEvents.close();
  
  // Test with event listener
  cleanDb('./with-events-test');
  const storeWithEvents = new ElkynStore({ 
    mode: 'standalone', 
    dataDir: './with-events-test'
  });
  
  let eventCount = 0;
  const subscription = storeWithEvents.watch('/test').subscribe((event) => {
    eventCount++;
  });
  
  console.log('Testing writes with active event listener...');
  const withEventsStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    storeWithEvents.set(`/test/${i}`, { data: 'test', id: i });
  }
  
  const withEventsElapsed = Date.now() - withEventsStart;
  const withEventsOpsPerSec = Math.round((iterations / withEventsElapsed) * 1000);
  
  console.log(`With Events: ${withEventsOpsPerSec.toLocaleString()} ops/sec (${eventCount} events)`);
  
  subscription.unsubscribe();
  storeWithEvents.close();
  
  return {
    noEvents: noEventsOpsPerSec,
    withEvents: withEventsOpsPerSec
  };
}

function testNAPIOverhead() {
  console.log('\n🔥 N-API Bridge Overhead Test\n');
  
  const iterations = 10000;
  
  // Test direct LMDB N-API calls
  cleanDb('./napi-test');
  const db = open({ path: './napi-test' });
  
  console.log('Testing direct LMDB puts...');
  const directStart = Date.now();
  
  db.transactionSync(() => {
    for (let i = 0; i < iterations; i++) {
      db.put(`test${i}`, 'simple string');
    }
  });
  
  const directElapsed = Date.now() - directStart;
  const directOpsPerSec = Math.round((iterations / directElapsed) * 1000);
  
  console.log(`Direct LMDB: ${directOpsPerSec.toLocaleString()} ops/sec`);
  
  db.close();
  
  // Test Elkyn simple string writes (minimal processing)
  cleanDb('./elkyn-simple-test');
  const store = new ElkynStore({ 
    mode: 'standalone', 
    dataDir: './elkyn-simple-test'
  });
  
  console.log('Testing Elkyn simple string writes...');
  const elkynStart = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    store.set(`/test/${i}`, 'simple string');
  }
  
  const elkynElapsed = Date.now() - elkynStart;
  const elkynOpsPerSec = Math.round((iterations / elkynElapsed) * 1000);
  
  console.log(`Elkyn Simple: ${elkynOpsPerSec.toLocaleString()} ops/sec`);
  
  store.close();
  
  return {
    direct: directOpsPerSec,
    elkyn: elkynOpsPerSec
  };
}

function analyzeBottlenecks() {
  console.log('🔍 Comprehensive Bottleneck Analysis\n');
  console.log('='.repeat(60));
  
  const serializationResults = testMessagePackOverhead();
  const eventResults = testEventOverhead();
  const napiResults = testNAPIOverhead();
  
  console.log('\n📊 BOTTLENECK SUMMARY');
  console.log('='.repeat(60));
  
  console.log('\n🎯 Serialization Impact:');
  const serializationOverhead = serializationResults.json / serializationResults.msgpack;
  console.log(`   JSON:              ${serializationResults.json.toLocaleString()} ops/sec`);
  console.log(`   LMDB built-in:     ${serializationResults.msgpack.toLocaleString()} ops/sec`);
  console.log(`   Overhead:          ${serializationOverhead.toFixed(1)}x slower`);
  
  console.log('\n🎯 Event System Impact:');
  const eventOverhead = eventResults.noEvents / eventResults.withEvents;
  console.log(`   No events:         ${eventResults.noEvents.toLocaleString()} ops/sec`);
  console.log(`   With events:       ${eventResults.withEvents.toLocaleString()} ops/sec`);
  console.log(`   Overhead:          ${eventOverhead.toFixed(1)}x slower`);
  
  console.log('\n🎯 N-API Bridge Impact:');
  const napiOverhead = napiResults.direct / napiResults.elkyn;
  console.log(`   Direct LMDB:       ${napiResults.direct.toLocaleString()} ops/sec`);
  console.log(`   Elkyn (simple):    ${napiResults.elkyn.toLocaleString()} ops/sec`);
  console.log(`   Overhead:          ${napiOverhead.toFixed(1)}x slower`);
  
  console.log('\n🏆 Performance Optimization Priorities:');
  
  const overheads = [
    ['Event System', eventOverhead],
    ['N-API Bridge', napiOverhead],
    ['Serialization', serializationOverhead]
  ].sort((a, b) => b[1] - a[1]);
  
  overheads.forEach(([name, overhead], index) => {
    const priority = index === 0 ? '🔥 HIGH' : index === 1 ? '🟡 MEDIUM' : '🟢 LOW';
    console.log(`   ${index + 1}. ${name}: ${overhead.toFixed(1)}x overhead - ${priority} priority`);
  });
  
  console.log('\n💡 Actionable Optimizations:');
  
  if (overheads[0][0] === 'Event System') {
    console.log('   1. 🎯 Skip event emission when no listeners registered');
    console.log('   2. 🎯 Make event processing async (don\'t block writes)');
    console.log('   3. 🎯 Batch events for multiple operations');
  }
  
  if (overheads.find(([name]) => name === 'N-API Bridge')?.[1] > 2) {
    console.log('   4. 🎯 Reduce N-API calls by batching operations');
    console.log('   5. 🎯 Use fewer string conversions between JS and Zig');
    console.log('   6. 🎯 Optimize memory allocations in Zig code');
  }
  
  console.log('\n✅ Low-hanging fruit:');
  console.log('   • Conditional event emission (easy win)');
  console.log('   • Remove debug allocations');
  console.log('   • Skip JSON parsing for simple strings');
  console.log('   • Use stack allocation for small values');
  
  return {
    serialization: serializationResults,
    events: eventResults,
    napi: napiResults,
    priorities: overheads
  };
}

analyzeBottlenecks();