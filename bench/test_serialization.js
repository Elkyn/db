#!/usr/bin/env node

const msgpack = require('msgpackr');

console.log('🔍 Serialization Performance Test\n');

const iterations = 100000;

// Test data
const stringValue = "Hello World Test String";
const numberValue = 42.123456;
const boolValue = true;
const objectValue = { id: 1, name: "Test", active: true };

// Test 1: MessagePack for primitives
console.log('1️⃣  MessagePack Serialization');

// String
let start = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const packed = msgpack.pack(stringValue);
  const unpacked = msgpack.unpack(packed);
}
let end = process.hrtime.bigint();
let time = Number(end - start) / 1e9;
console.log(`   String: ${Math.round(iterations / time).toLocaleString()} ops/sec`);

// Number
start = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const packed = msgpack.pack(numberValue);
  const unpacked = msgpack.unpack(packed);
}
end = process.hrtime.bigint();
time = Number(end - start) / 1e9;
console.log(`   Number: ${Math.round(iterations / time).toLocaleString()} ops/sec`);

// Test 2: Direct Buffer operations
console.log('\n2️⃣  Direct Buffer Operations');

// String (just UTF-8 encoding)
start = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const buf = Buffer.from(stringValue, 'utf8');
  const str = buf.toString('utf8');
}
end = process.hrtime.bigint();
time = Number(end - start) / 1e9;
console.log(`   String: ${Math.round(iterations / time).toLocaleString()} ops/sec`);

// Number (as float64)
start = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const buf = Buffer.allocUnsafe(8);
  buf.writeDoubleLE(numberValue);
  const num = buf.readDoubleLE();
}
end = process.hrtime.bigint();
time = Number(end - start) / 1e9;
console.log(`   Number: ${Math.round(iterations / time).toLocaleString()} ops/sec`);

// Test 3: JSON (for comparison)
console.log('\n3️⃣  JSON Serialization');

start = process.hrtime.bigint();
for (let i = 0; i < iterations; i++) {
  const json = JSON.stringify(stringValue);
  const parsed = JSON.parse(json);
}
end = process.hrtime.bigint();
time = Number(end - start) / 1e9;
console.log(`   String: ${Math.round(iterations / time).toLocaleString()} ops/sec`);

console.log('\n📊 Summary:');
console.log('- Direct buffer operations are fastest for primitives');
console.log('- MessagePack adds overhead for simple values');
console.log('- For decomposed storage, consider type-specific encoding');