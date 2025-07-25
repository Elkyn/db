#!/usr/bin/env node

const { ElkynStore } = require('../nodejs-bindings');
const fs = require('fs');

console.log('🏃 Elkyn DB Performance Benchmark\n');

const iterations = 10000;
const dataDir = './bench-' + Date.now();

// Initialize store
const store = new ElkynStore({ 
  mode: 'standalone', 
  dataDir: dataDir
});

// Test data
const testData = { 
  id: 1, 
  name: 'Test User', 
  email: 'test@example.com',
  active: true,
  score: 95.5,
  metadata: { 
    created: Date.now(), 
    tags: ['user', 'test', 'benchmark'],
    nested: {
      level: 2,
      data: 'nested value'
    }
  }
};

console.log('Running benchmarks with', iterations, 'iterations...\n');

// Write benchmark
console.log('1️⃣  Write Performance');
const writeStart = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  store.set(`/users/user${i}`, testData);
}
const writeEnd = process.hrtime.bigint();
const writeTime = Number(writeEnd - writeStart) / 1e9;
const writeOpsPerSec = Math.round(iterations / writeTime);

console.log(`   ✅ ${writeOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   ⏱️  ${writeTime.toFixed(3)}s for ${iterations.toLocaleString()} operations`);

// Read benchmark
console.log('\n2️⃣  Read Performance');
const readStart = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const data = store.get(`/users/user${i}`);
}
const readEnd = process.hrtime.bigint();
const readTime = Number(readEnd - readStart) / 1e9;
const readOpsPerSec = Math.round(iterations / readTime);

console.log(`   ✅ ${readOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   ⏱️  ${readTime.toFixed(3)}s for ${iterations.toLocaleString()} operations`);

// Field access benchmark
console.log('\n3️⃣  Field Access Performance');
const fieldStart = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const name = store.get(`/users/user${i}/name`);
}
const fieldEnd = process.hrtime.bigint();
const fieldTime = Number(fieldEnd - fieldStart) / 1e9;
const fieldOpsPerSec = Math.round(iterations / fieldTime);

console.log(`   ✅ ${fieldOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   ⏱️  ${fieldTime.toFixed(3)}s for ${iterations.toLocaleString()} operations`);

// Array operations
console.log('\n4️⃣  Array Operations');
const arrayData = [1, 2, 3, { id: 4 }, { id: 5, name: 'five' }];
const arrayStart = process.hrtime.bigint();
for (let i = 0; i < iterations / 10; i++) {
  store.set(`/arrays/arr${i}`, arrayData);
  const retrieved = store.get(`/arrays/arr${i}`);
}
const arrayEnd = process.hrtime.bigint();
const arrayTime = Number(arrayEnd - arrayStart) / 1e9;
const arrayOpsPerSec = Math.round((iterations / 10) / arrayTime);

console.log(`   ✅ ${arrayOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   ⏱️  ${arrayTime.toFixed(3)}s for ${(iterations/10).toLocaleString()} operations`);

// Summary
console.log('\n' + '='.repeat(60));
console.log('📊 Performance Summary');
console.log('='.repeat(60));
console.log(`   Write:       ${writeOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   Read:        ${readOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   Field Access: ${fieldOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   Arrays:      ${arrayOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   Average:     ${Math.round((writeOpsPerSec + readOpsPerSec + fieldOpsPerSec) / 3).toLocaleString()} ops/sec`);

// Compare with previous results
console.log('\n📈 Performance Improvements:');
console.log('   Previous write: ~10,707 ops/sec');
console.log(`   Current write:  ${writeOpsPerSec.toLocaleString()} ops/sec`);
console.log(`   Improvement:    ${((writeOpsPerSec / 10707 - 1) * 100).toFixed(1)}%`);

// Cleanup
store.close();
if (fs.existsSync(dataDir)) {
  fs.rmSync(dataDir, { recursive: true });
}

console.log('\n✅ Benchmark complete!');