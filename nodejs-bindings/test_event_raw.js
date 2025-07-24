const { ElkynStore } = require('./index');

console.log('Testing raw event values...');

const store = new ElkynStore({ mode: 'standalone', dataDir: './test-raw' });

// Watch for changes and display raw event data
const sub = store.watch('/*')
    .subscribe(event => {
        console.log('Event:', {
            type: event.type,
            path: event.path,
            value: event.value,
            valueType: typeof event.value,
            timestamp: event.timestamp
        });
    });

// Set different types of values
setTimeout(() => {
    console.log('\nSetting values...');
    
    store.set('/string', 'Hello World');
    store.set('/number', 42);
    store.set('/boolean', true);
    store.set('/object', { name: 'Test', count: 123 });
    store.set('/array', [1, 2, 3]);
    store.set('/null', null);
    
    store.delete('/string');
}, 100);

// Cleanup
setTimeout(() => {
    sub.unsubscribe();
    store.close();
    console.log('\nDone!');
}, 1000);