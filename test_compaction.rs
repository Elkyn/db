// Test compaction functionality
use std::path::Path;
use std::fs;
use std::thread;
use std::time::Duration;

mod antler_store {
    include!("antler.rs");
}

use antler_store::*;

fn main() {
    let dir = "/tmp/antler_compaction_test";
    let _ = fs::remove_dir_all(dir);
    
    println!("Testing Compaction...");
    println!("====================");
    
    // Create store
    let store = Store::open(Path::new(dir)).unwrap();
    
    // Phase 1: Create enough segments to trigger L0 compaction
    println!("\nPhase 1: Creating L0 segments...");
    
    for batch in 0..5 {  // 5 batches = 5 L0 segments
        println!("  Writing batch {}...", batch);
        for i in 0..100 {
            let key = format!("batch{}/key{:03}", batch, i);
            store.set(&key, &format!("value_{}", batch * 100 + i), false).unwrap();
        }
        store.flush().unwrap();
        println!("  Flushed batch {} to L0", batch);
    }
    
    // Check L0 segments before compaction
    {
        let (l0, l1, l2) = store.segment_counts();
        println!("\nBefore compaction:");
        println!("  L0 segments: {}", l0);
        println!("  L1 segments: {}", l1);
        println!("  L2 segments: {}", l2);
    }
    
    // Wait for compaction to run (compaction thread runs every 5 seconds)
    println!("\nWaiting for L0->L1 compaction (6 seconds)...");
    thread::sleep(Duration::from_secs(6));
    
    // Check segments after L0 compaction
    {
        let (l0, l1, l2) = store.segment_counts();
        println!("\nAfter L0->L1 compaction:");
        println!("  L0 segments: {}", l0);
        println!("  L1 segments: {}", l1);
        println!("  L2 segments: {}", l2);
    }
    
    // Verify data is still accessible
    println!("\nVerifying data integrity...");
    let test_keys = vec![
        "batch0/key000",
        "batch1/key050",
        "batch2/key099",
        "batch3/key001",
        "batch4/key099",
    ];
    
    for key in test_keys {
        match store.get(key).unwrap() {
            Some(_) => print!("✓"),
            None => {
                println!("\n❌ Key {} not found after compaction!", key);
                std::process::exit(1);
            }
        }
    }
    println!(" All test keys found!");
    
    // Phase 2: Create more L0 segments to have multiple L1 segments
    println!("\nPhase 2: Creating more segments for L1->L2 compaction...");
    
    for round in 0..12 {  // Create 12 more segments (3 compactions = 3 L1 segments)
        for i in 0..50 {
            let key = format!("round{}/key{:03}", round, i);
            store.set(&key, &format!("value_r{}", round * 50 + i), false).unwrap();
        }
        store.flush().unwrap();
        
        if round % 4 == 3 {
            // Wait for L0->L1 compaction
            println!("  Round {}: waiting for compaction...", round);
            thread::sleep(Duration::from_secs(6));
        }
    }
    
    // Final check
    {
        let (l0, l1, l2) = store.segment_counts();
        println!("\nFinal segment distribution:");
        println!("  L0 segments: {}", l0);
        println!("  L1 segments: {}", l1);
        println!("  L2 segments: {}", l2);
    }
    
    // Test updates and tombstones
    println!("\nTesting updates and tombstones...");
    
    // Update some keys
    store.set("batch0/key000", "updated_value", false).unwrap();
    store.delete("batch1/key050").unwrap();
    store.flush().unwrap();
    
    // Wait for potential compaction
    thread::sleep(Duration::from_secs(6));
    
    // Verify updates
    match store.get("batch0/key000").unwrap() {
        Some(v) if v == "updated_value" => println!("  ✓ Update preserved after compaction"),
        _ => {
            println!("  ❌ Update lost after compaction!");
            std::process::exit(1);
        }
    }
    
    match store.get("batch1/key050").unwrap() {
        None => println!("  ✓ Delete preserved after compaction"),
        Some(_) => {
            println!("  ❌ Deleted key still exists after compaction!");
            std::process::exit(1);
        }
    }
    
    // Check disk usage
    let entries = fs::read_dir(dir).unwrap();
    let seg_files: Vec<_> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension() == Some("seg".as_ref()))
        .collect();
    
    println!("\nDisk usage:");
    println!("  Total segment files: {}", seg_files.len());
    
    for file in &seg_files {
        let metadata = file.metadata().unwrap();
        let name = file.file_name();
        println!("    {} ({} bytes)", name.to_string_lossy(), metadata.len());
    }
    
    println!("\n✅ Compaction test passed!");
    
    // Cleanup
    drop(store);
    let _ = fs::remove_dir_all(dir);
}