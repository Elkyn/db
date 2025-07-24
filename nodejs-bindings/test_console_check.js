// Test console.log behavior
const obj = { name: 'Test', count: 1 };
const str = '{"name":"Test","count":1}';

console.log('Object:', obj);
console.log('String:', str);
console.log('');

// Now in one line like our debug
console.log('Type and value - Object:', typeof obj, obj);
console.log('Type and value - String:', typeof str, str);