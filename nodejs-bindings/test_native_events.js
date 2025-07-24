const { ElkynStore } = require('./index');

console.log('🔧 Testing Native Event System\n');

async function testNativeEvents() {
    const store = new ElkynStore({ mode: 'standalone', dataDir: './test-events' });
    
    console.log('1️⃣ Testing direct native watch:');
    
    // Test direct native watch
    const subscription = store._watchNative('/test/*', (event) => {
        console.log(`  Native event received:`, event);
    });
    
    console.log(`  Subscription ID: ${subscription}`);
    
    // Wait a moment for the subscription to be fully set up
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Trigger some changes
    console.log('\n2️⃣ Triggering changes:');
    store.set('/test/item1', { name: 'Item 1' });
    store.set('/test/item2', { name: 'Item 2' });
    store.delete('/test/item1');
    
    // Give events time to process
    await new Promise(resolve => setTimeout(resolve, 200));
    
    console.log('\n3️⃣ Testing Observable API:');
    const observable = store.watch('/users/*');
    const sub = observable.subscribe(event => {
        console.log(`  Observable event:`, event);
    });
    
    // Trigger more changes
    store.set('/users/alice', { name: 'Alice', age: 30 });
    store.set('/users/bob', { name: 'Bob', age: 25 });
    
    // Give events time to process
    await new Promise(resolve => setTimeout(resolve, 200));
    
    console.log('\n4️⃣ Cleanup:');
    store._unwatchNative(subscription);
    sub.unsubscribe();
    store.close();
    
    console.log('✅ Test complete!');
}

testNativeEvents().catch(console.error);