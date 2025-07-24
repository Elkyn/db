const { ElkynStore } = require('./index');

async function testObservableAPI() {
    console.log('🔭 Testing Observable API for Elkyn Store\n');

    const store = new ElkynStore({ mode: 'standalone', dataDir: './test-observable' });

    // Example 1: Basic subscription
    console.log('1️⃣ Basic subscription:');
    const subscription = store.watch('/users/123')
        .subscribe(event => {
            console.log(`  Event: ${event.type} at ${event.path}`);
            console.log(`  Value:`, event.value);
        });

    // Simulate some changes
    store.set('/users/123', { name: 'Alice', age: 30 });
    store.set('/users/123/name', 'Alice Smith');
    store.delete('/users/123/age');

    // Example 2: Wildcard watching
    console.log('\n2️⃣ Wildcard subscription:');
    const wildcard = store.watch('/users/*')
        .subscribe(event => {
            console.log(`  User event: ${event.type} at ${event.path}`);
        });

    store.set('/users/456', { name: 'Bob' });
    store.set('/users/789', { name: 'Charlie' });

    // Example 3: Filtered events
    console.log('\n3️⃣ Filtered events (only changes, not deletes):');
    store.watch('/products/*')
        .filter(event => event.type === 'change')
        .subscribe(event => {
            console.log(`  Product changed: ${event.path}`);
        });

    store.set('/products/laptop', { price: 999 });
    store.delete('/products/old-item'); // This won't show

    // Example 4: Mapped events
    console.log('\n4️⃣ Mapped events (extract just the name):');
    store.watch('/users/*')
        .filter(event => event.type === 'change' && event.value?.name)
        .map(event => ({
            userId: event.path.split('/').pop(),
            name: event.value.name
        }))
        .subscribe(user => {
            console.log(`  User ${user.userId} is named ${user.name}`);
        });

    store.set('/users/alice', { name: 'Alice Cooper', role: 'admin' });

    // Example 5: Debounced events
    console.log('\n5️⃣ Debounced events (wait 100ms):');
    store.watch('/config/*')
        .debounce(100)
        .subscribe(event => {
            console.log(`  Config updated: ${event.path}`);
        });

    // Rapid updates - only last one should trigger
    store.set('/config/theme', 'light');
    store.set('/config/theme', 'dark');
    store.set('/config/theme', 'auto');

    // Example 6: Take first N events
    console.log('\n6️⃣ Take first 3 events:');
    store.watch('/logs/*')
        .take(3)
        .subscribe({
            next: event => console.log(`  Log: ${event.path}`),
            complete: () => console.log('  Completed after 3 events!')
        });

    for (let i = 1; i <= 5; i++) {
        store.set(`/logs/entry${i}`, { message: `Log ${i}` });
    }

    // Example 7: Async iterator
    console.log('\n7️⃣ Async iterator pattern:');
    (async () => {
        const watcher = store.watch('/stream/*');
        setTimeout(() => {
            store.set('/stream/1', { data: 'first' });
            store.set('/stream/2', { data: 'second' });
            store.set('/stream/3', { data: 'third' });
        }, 50);

        let count = 0;
        for await (const event of watcher) {
            console.log(`  Stream event: ${event.path}`);
            if (++count >= 3) break;
        }
        console.log('  Stream iteration complete');
    })();

    // Cleanup
    setTimeout(() => {
        console.log('\n🧹 Cleaning up subscriptions...');
        subscription.unsubscribe();
        wildcard.unsubscribe();
        store.close();
        console.log('✅ Test complete!');
    }, 500);
}

// Note about implementation status
console.log('✅  Testing actual event delivery from Zig core!\n');

testObservableAPI().catch(console.error);