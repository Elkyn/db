// Test JSON.parse directly
const testValues = [
    '{"name":"Test","count":1}',
    '"Just a string"',
    '42',
    'true',
    'null',
    '[1,2,3]'
];

console.log('Testing JSON.parse directly:\n');

testValues.forEach(val => {
    try {
        const parsed = JSON.parse(val);
        console.log(`Input: ${val}`);
        console.log(`  Type: ${typeof parsed}`);
        console.log(`  Value:`, parsed);
        console.log(`  Stringified:`, JSON.stringify(parsed));
        console.log();
    } catch (e) {
        console.log(`Failed to parse: ${val} - ${e.message}\n`);
    }
});