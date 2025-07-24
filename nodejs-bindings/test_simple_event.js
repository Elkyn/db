const { ElkynStore } = require('./index');

console.log('Testing simple event...');

const store = new ElkynStore({ mode: 'standalone', dataDir: './test-simple' });

// Set up watch first
let received = false;
const sub = store._watchNative('/test', (event) => {
    console.log('🎉 GOT EVENT!', JSON.stringify(event));
    received = true;
});

// Wait a bit then trigger
setTimeout(() => {
    console.log('Setting value...');
    store.set('/test', { hello: 'world' });
    
    setTimeout(() => {
        console.log('Received:', received);
        store.close();
        process.exit(received ? 0 : 1);
    }, 1000);
}, 100);