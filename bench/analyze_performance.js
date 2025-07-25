#!/usr/bin/env node

const { ElkynStore } = require('../nodejs-bindings');
const fs = require('fs');
const lmdb = require('lmdb');

console.log('🔍 Performance Analysis: Elkyn vs Raw LMDB\n');

const iterations = 10000;

// Test 1: Raw LMDB performance
console.log('1️⃣  Raw LMDB Performance');
const lmdbDir = './bench-lmdb-' + Date.now();
const db = lmdb.open({
  path: lmdbDir,
  compression: false,
  mapSize: 100 * 1024 * 1024
});

const testData = { 
  id: 1, 
  name: 'Test User', 
  email: 'test@example.com',
  active: true,
  score: 95.5
};

// LMDB Write
const lmdbWriteStart = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  db.put(`user${i}`, testData);
}
const lmdbWriteEnd = process.hrtime.bigint();
const lmdbWriteTime = Number(lmdbWriteEnd - lmdbWriteStart) / 1e9;
const lmdbWriteOps = Math.round(iterations / lmdbWriteTime);

console.log(`   Write: ${lmdbWriteOps.toLocaleString()} ops/sec`);

// LMDB Read
const lmdbReadStart = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const data = db.get(`user${i}`);
}
const lmdbReadEnd = process.hrtime.bigint();
const lmdbReadTime = Number(lmdbReadEnd - lmdbReadStart) / 1e9;
const lmdbReadOps = Math.round(iterations / lmdbReadTime);

console.log(`   Read:  ${lmdbReadOps.toLocaleString()} ops/sec`);

db.close();

// Test 2: Elkyn with MessagePack
console.log('\n2️⃣  Elkyn Performance (with MessagePack)');
const elkynDir = './bench-elkyn-' + Date.now();
const store = new ElkynStore({ 
  mode: 'standalone', 
  dataDir: elkynDir
});

// Elkyn Write
const elkynWriteStart = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  store.set(`/users/user${i}`, testData);
}
const elkynWriteEnd = process.hrtime.bigint();
const elkynWriteTime = Number(elkynWriteEnd - elkynWriteStart) / 1e9;
const elkynWriteOps = Math.round(iterations / elkynWriteTime);

console.log(`   Write: ${elkynWriteOps.toLocaleString()} ops/sec`);

// Elkyn Read
const elkynReadStart = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const data = store.get(`/users/user${i}`);
}
const elkynReadEnd = process.hrtime.bigint();
const elkynReadTime = Number(elkynReadEnd - elkynReadStart) / 1e9;
const elkynReadOps = Math.round(iterations / elkynReadTime);

console.log(`   Read:  ${elkynReadOps.toLocaleString()} ops/sec`);

// Test 3: Simple values (strings/numbers)
console.log('\n3️⃣  Simple Value Performance');
const simpleWriteStart = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  store.setString(`/simple/str${i}`, 'Hello World ' + i);
}
const simpleWriteEnd = process.hrtime.bigint();
const simpleWriteTime = Number(simpleWriteEnd - simpleWriteStart) / 1e9;
const simpleWriteOps = Math.round(iterations / simpleWriteTime);

console.log(`   String Write: ${simpleWriteOps.toLocaleString()} ops/sec`);

// Analysis
console.log('\n' + '='.repeat(60));
console.log('📊 Performance Analysis');
console.log('='.repeat(60));
console.log(`LMDB Raw Write:   ${lmdbWriteOps.toLocaleString()} ops/sec`);
console.log(`Elkyn Write:      ${elkynWriteOps.toLocaleString()} ops/sec`);
console.log(`Overhead:         ${((lmdbWriteOps / elkynWriteOps) - 1).toFixed(1)}x slower`);
console.log('');
console.log(`LMDB Raw Read:    ${lmdbReadOps.toLocaleString()} ops/sec`);
console.log(`Elkyn Read:       ${elkynReadOps.toLocaleString()} ops/sec`);
console.log(`Overhead:         ${((lmdbReadOps / elkynReadOps) - 1).toFixed(1)}x slower`);

console.log('\n🔍 Bottleneck Analysis:');
console.log('1. N-API Bridge overhead (crossing JS/Native boundary)');
console.log('2. Object decomposition (storing each field separately)');
console.log('3. Path normalization and validation');
console.log('4. MessagePack serialization/deserialization');

// Cleanup
store.close();
if (fs.existsSync(elkynDir)) {
  fs.rmSync(elkynDir, { recursive: true });
}
if (fs.existsSync(lmdbDir)) {
  fs.rmSync(lmdbDir, { recursive: true });
}