const { ElkynStore } = require('./index');

console.log('Clean test of event system with JSON parsing\n');

const store = new ElkynStore({ mode: 'standalone', dataDir: './test-clean' });

// Direct subscription - should show parsed values
console.log('1. Direct subscription:');
store.watch('/test/*')
    .subscribe(event => {
        console.log('  Event:', {
            path: event.path,
            type: event.type,
            value: event.value,
            valueType: typeof event.value
        });
    });

// Filtered and mapped - should work with parsed values
console.log('\n2. Filtered and mapped:');
store.watch('/users/*')
    .filter(e => e.type === 'change')
    .map(e => ({
        userId: e.path.split('/').pop(),
        name: e.value?.name,
        age: e.value?.age
    }))
    .subscribe(user => {
        console.log('  User:', user);
    });

// Set some values
setTimeout(() => {
    console.log('\nSetting values...\n');
    
    store.set('/test/string', 'Hello');
    store.set('/test/object', { foo: 'bar' });
    store.set('/users/alice', { name: 'Alice', age: 30 });
    store.set('/users/bob', { name: 'Bob', age: 25 });
}, 100);

// Clean up
setTimeout(() => {
    store.close();
    console.log('\nDone!');
}, 500);