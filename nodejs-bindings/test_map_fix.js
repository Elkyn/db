const { ElkynStore } = require('./index');

console.log('Testing map with value parsing...');

const store = new ElkynStore({ mode: 'standalone', dataDir: './test-map' });

// Watch and parse the value
store.watch('/users/*')
    .filter(e => e.type === 'change')
    .map(e => {
        console.log('Raw event:', e);
        // Since value comes as JSON string, parse it
        let parsedValue;
        try {
            parsedValue = typeof e.value === 'string' ? JSON.parse(e.value) : e.value;
        } catch (err) {
            parsedValue = e.value;
        }
        return {
            userId: e.path.split('/').pop(),
            name: parsedValue?.name,
            raw: e.value
        };
    })
    .subscribe(user => {
        console.log('Mapped user:', user);
    });

setTimeout(() => {
    console.log('\nSetting user...');
    store.set('/users/alice', { name: 'Alice Cooper', age: 30 });
}, 100);

setTimeout(() => {
    store.close();
    console.log('\nDone!');
}, 500);