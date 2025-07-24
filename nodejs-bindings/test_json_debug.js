const { ElkynStore } = require('./index');

console.log('Testing JSON parsing in detail\n');

const store = new ElkynStore({ mode: 'standalone', dataDir: './test-json' });

// Test direct subscription
console.log('1. Testing direct subscription:');
const sub1 = store.watch('/direct')
    .subscribe(event => {
        console.log('  Direct event:', {
            value: event.value,
            type: typeof event.value,
            isObject: event.value !== null && typeof event.value === 'object',
            raw: JSON.stringify(event)
        });
    });

// Test with filter
console.log('\n2. Testing with filter:');
const sub2 = store.watch('/filter')
    .filter(e => e.type === 'change')
    .subscribe(event => {
        console.log('  Filtered event:', {
            value: event.value,
            type: typeof event.value,
            isObject: event.value !== null && typeof event.value === 'object'
        });
    });

// Test with map
console.log('\n3. Testing with map:');
const sub3 = store.watch('/map')
    .map(e => ({
        original: e.value,
        type: typeof e.value,
        extracted: e.value?.name
    }))
    .subscribe(mapped => {
        console.log('  Mapped:', mapped);
    });

setTimeout(() => {
    console.log('\nSetting values...\n');
    
    // Objects
    store.set('/direct', { name: 'Direct Object', count: 1 });
    store.set('/filter', { name: 'Filtered Object', count: 2 });
    store.set('/map', { name: 'Mapped Object', count: 3 });
    
    // Strings
    store.set('/direct', 'Just a string');
    store.set('/filter', 'Another string');
    
    // Numbers
    store.set('/direct', 42);
    store.set('/filter', 123);
}, 100);

setTimeout(() => {
    sub1.unsubscribe();
    sub2.unsubscribe();
    sub3.unsubscribe();
    store.close();
    console.log('\nDone!');
}, 500);