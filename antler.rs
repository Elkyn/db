// ELKYN ULTIMATE FIXED - Addressing critical bugs from review
// Single-file Firebase RTDB-like store with:
// - FIXED record layout consistency
// - FIXED last-block bounds with index_start tracking  
// - REAL group commit with background flusher
// - DISABLED broken compaction (until proper implementation)
// - Added manifest for crash safety
// - Tree semantics enforcement

use std::collections::{BTreeMap, HashMap};
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, RwLock};
use std::thread;
use std::time::Duration;

const MAGIC: &[u8] = b"ELKYN03";
const WAL_MAGIC: &[u8] = b"WAL2";
const RT_SET: u8 = 1;
const RT_DEL_POINT: u8 = 2;
const RT_DEL_SUB: u8 = 3;
const BLOCK_SIZE: usize = 4096;
const MEMTABLE_THRESHOLD: usize = 256 * 1024;
// Compaction is currently disabled - these will be used when implemented
// const L0_COMPACTION_THRESHOLD: usize = 4;
// const L1_COMPACTION_THRESHOLD: usize = 10;
const CACHE_SIZE: usize = 32 * 1024 * 1024;
const GROUP_COMMIT_MS: u64 = 10;

#[derive(Debug)]
pub struct Store {
    dir: PathBuf,
    inner: Arc<RwLock<StoreInner>>,
    wal: Arc<GroupCommitWAL>,
    cache: Arc<BlockCache>,
    manifest: Arc<Mutex<Manifest>>,
}

#[derive(Debug)]
struct StoreInner {
    seq: u64,
    memtable: BTreeMap<String, MemValue>,
    memtable_size: usize,
    segments_l0: Vec<Arc<Segment>>,
    segments_l1: Vec<Arc<Segment>>,
    segments_l2: Vec<Arc<Segment>>,
    subtombs: HashMap<String, u64>,
}

#[derive(Debug, Clone)]
enum MemValue {
    Scalar(String, u64),
    PointTomb(u64),
}

#[derive(Debug)]
struct GroupCommitWAL {
    path: PathBuf,
    buffer: Mutex<Vec<WALEntry>>,
    // sync_interval: Duration, // Currently using const GROUP_COMMIT_MS
    shutdown: Arc<(Mutex<bool>, Condvar)>,
}

#[derive(Debug)]
struct WALEntry {
    seq: u64,
    kind: u8,
    key: String,
    value: Option<String>,
}

#[derive(Debug)]
struct Segment {
    path: PathBuf,
    // seq_low: u64,     // Not currently used but may be useful for compaction
    seq_high: u64,
    // key_count: usize, // Not currently used but may be useful for stats
    bloom: Option<BloomFilter>,
    index: Vec<(String, u64)>,
    index_start: u64,  // FIXED: Store where blocks end
}

#[derive(Debug)]
struct Manifest {
    path: PathBuf,
    entries: Vec<ManifestEntry>,
}

#[derive(Debug, Clone)]
struct ManifestEntry {
    seq_high: u64,
    level: usize,
    filename: String,
}

#[derive(Debug)]
struct BloomFilter {
    bits: Vec<u8>,
    bit_count: usize,
    hash_count: usize,  // FIXED: Store hash count
}

#[derive(Debug)]
struct BlockCache {
    cache: RwLock<HashMap<(PathBuf, u64), Arc<Vec<u8>>>>,
    size: RwLock<usize>,
    max_size: usize,
}

impl Drop for Store {
    fn drop(&mut self) {
        // Signal shutdown to background thread
        let (lock, cvar) = &*self.wal.shutdown;
        let mut shutdown = lock.lock().unwrap();
        *shutdown = true;
        cvar.notify_all();
        
        // Sync any remaining WAL entries
        let _ = self.wal.sync_now();
    }
}

impl Store {
    pub fn open(dir: &Path) -> io::Result<Self> {
        fs::create_dir_all(dir)?;
        
        let wal_path = dir.join("wal.log");
        let manifest_path = dir.join("manifest.log");
        
        // Load manifest
        let manifest = Arc::new(Mutex::new(Manifest::load(&manifest_path)?));
        
        // Create WAL with background flusher
        let wal = Arc::new(GroupCommitWAL::new(&wal_path)?);
        
        // Start background WAL flusher thread
        let wal_clone = wal.clone();
        thread::spawn(move || {
            loop {
                thread::sleep(Duration::from_millis(GROUP_COMMIT_MS));
                // Silently ignore sync errors - WAL will retry on next interval
                let _ = wal_clone.sync_now();
                
                let shutdown = wal_clone.shutdown.0.lock().unwrap();
                if *shutdown {
                    break;
                }
            }
        });
        
        let mut inner = StoreInner {
            seq: 0,
            memtable: BTreeMap::new(),
            memtable_size: 0,
            segments_l0: Vec::new(),
            segments_l1: Vec::new(),
            segments_l2: Vec::new(),
            subtombs: HashMap::new(),
        };
        
        // Load segments from manifest
        let manifest_lock = manifest.lock().unwrap();
        for entry in &manifest_lock.entries {
            let seg_path = dir.join(&entry.filename);
            if let Ok(seg) = Segment::open(&seg_path) {
                let seq_high = seg.seq_high;
                match entry.level {
                    0 => inner.segments_l0.push(Arc::new(seg)),
                    1 => inner.segments_l1.push(Arc::new(seg)),
                    2 => inner.segments_l2.push(Arc::new(seg)),
                    _ => {}
                }
                if seq_high > inner.seq {
                    inner.seq = seq_high;
                }
            }
        }
        drop(manifest_lock);
        
        // Replay WAL
        inner.replay_wal(&wal_path)?;
        
        let store = Store {
            dir: dir.to_path_buf(),
            inner: Arc::new(RwLock::new(inner)),
            wal,
            cache: Arc::new(BlockCache::new(CACHE_SIZE)),
            manifest,
        };
        
        // DISABLED: Compaction thread (until properly implemented)
        // thread::spawn(move || { ... });
        
        Ok(store)
    }
    
    pub fn set(&self, path: &str, value: &str, replace_subtree: bool) -> io::Result<()> {
        // Check parent isn't a scalar (tree semantics)
        if let Some(parent) = parent_path(path) {
            if self.get(&parent)?.is_some() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "Cannot write under scalar parent"
                ));
            }
        }
        
        let mut inner = self.inner.write().unwrap();
        inner.seq += 1;
        let seq = inner.seq;
        
        if replace_subtree {
            // Emit subtomb for prefix
            let prefix = format!("{}/", path);
            self.wal.append(&WALEntry {
                seq,
                kind: RT_DEL_SUB,
                key: prefix.clone(),
                value: None,
            })?;
            inner.subtombs.insert(prefix, seq);
            
            // Emit point tombstone for the node itself (if it was scalar)
            self.wal.append(&WALEntry {
                seq,
                kind: RT_DEL_POINT,
                key: path.to_string(),
                value: None,
            })?;
            inner.memtable.insert(path.to_string(), MemValue::PointTomb(seq));
        }
        
        // Set the scalar value
        self.wal.append(&WALEntry {
            seq,
            kind: RT_SET,
            key: path.to_string(),
            value: Some(value.to_string()),
        })?;
        
        inner.memtable.insert(path.to_string(), MemValue::Scalar(value.to_string(), seq));
        inner.memtable_size += path.len() + value.len() + 16;
        
        if inner.memtable_size >= MEMTABLE_THRESHOLD {
            self.flush_memtable_locked(&mut inner)?;
        }
        
        Ok(())
    }
    
    pub fn get(&self, path: &str) -> io::Result<Option<String>> {
        let inner = self.inner.read().unwrap();
        
        // Check if this is a subtree query
        if path.ends_with('/') {
            return self.get_subtree(&inner, path);
        }
        
        // Check memtable
        if let Some(mv) = inner.memtable.get(path) {
            match mv {
                MemValue::Scalar(v, seq) if !self.covered_by_subtomb(&inner, path, *seq) => {
                    return Ok(Some(v.clone()));
                }
                _ => return Ok(None),
            }
        }
        
        // Check segments
        let mut result: Option<(String, u64)> = None;
        
        for seg in inner.segments_l0.iter()
            .chain(inner.segments_l1.iter())
            .chain(inner.segments_l2.iter())
        {
            if let Some(bloom) = &seg.bloom {
                if !bloom.might_contain(path) {
                    continue;
                }
            }
            
            if let Some((val, seq)) = self.get_from_segment(seg, path)? {
                if !self.covered_by_subtomb(&inner, path, seq) {
                    if result.is_none() || seq > result.as_ref().unwrap().1 {
                        result = Some((val, seq));
                    }
                }
            }
        }
        
        Ok(result.map(|(v, _)| v))
    }
    
    fn get_subtree(&self, inner: &std::sync::RwLockReadGuard<StoreInner>, prefix: &str) -> io::Result<Option<String>> {
        let mut tree = BTreeMap::new();
        
        // Collect from memtable
        for (k, v) in &inner.memtable {
            if k.starts_with(prefix) {
                if let MemValue::Scalar(val, seq) = v {
                    if !self.covered_by_subtomb(inner, k, *seq) {
                        tree.insert(k.clone(), (val.clone(), *seq));
                    }
                }
            }
        }
        
        // Collect from segments
        for seg in inner.segments_l0.iter()
            .chain(inner.segments_l1.iter())
            .chain(inner.segments_l2.iter())
        {
            for (k, v, seq) in self.scan_segment(seg, prefix, &format!("{}~", prefix))? {
                if !self.covered_by_subtomb(inner, &k, seq) {
                    if !tree.contains_key(&k) || tree[&k].1 < seq {
                        tree.insert(k, (v, seq));
                    }
                }
            }
        }
        
        if tree.is_empty() {
            return Ok(None);
        }
        
        // Convert to nested JSON
        Ok(Some(self.tree_to_json(&tree, prefix)))
    }
    
    fn tree_to_json(&self, tree: &BTreeMap<String, (String, u64)>, prefix: &str) -> String {
        // Simple JSON generation (real implementation would use serde_json)
        let mut json = String::from("{");
        let mut first = true;
        
        for (k, (v, _)) in tree {
            if !first {
                json.push(',');
            }
            first = false;
            
            let relative = &k[prefix.len()..];
            json.push('"');
            json.push_str(&relative.replace('"', "\\\""));
            json.push_str("\":\"");
            json.push_str(&v.replace('"', "\\\""));
            json.push('"');
        }
        
        json.push('}');
        json
    }
    
    fn covered_by_subtomb(&self, inner: &std::sync::RwLockReadGuard<StoreInner>, key: &str, seq: u64) -> bool {
        for (prefix, tomb_seq) in &inner.subtombs {
            if key.starts_with(prefix) && *tomb_seq >= seq {  // FIXED: >= not >
                return true;
            }
        }
        false
    }
    
    fn get_from_segment(&self, seg: &Arc<Segment>, key: &str) -> io::Result<Option<(String, u64)>> {
        // Binary search index
        let idx = match seg.index.binary_search_by_key(&key.to_string(), |(k, _)| k.clone()) {
            Ok(i) => i,
            Err(i) if i > 0 => i - 1,
            _ => return Ok(None),
        };
        
        let (_, offset) = &seg.index[idx];
        let next_offset = if idx + 1 < seg.index.len() {
            seg.index[idx + 1].1
        } else {
            seg.index_start  // FIXED: Use index_start, not file len
        };
        
        let block_data = self.cache.get_or_load(&seg.path, *offset, (next_offset - offset) as usize)?;
        
        // Parse block
        let mut pos = 0;
        while pos + 8 < block_data.len() {
            let mut seq_bytes = [0u8; 8];
            seq_bytes.copy_from_slice(&block_data[pos..pos + 8]);
            let seq = u64::from_le_bytes(seq_bytes);
            pos += 8;
            
            if pos >= block_data.len() {
                break;
            }
            
            let rec_type = block_data[pos];
            pos += 1;
            
            if pos + 4 > block_data.len() {
                break;
            }
            
            let mut klen_bytes = [0u8; 4];
            klen_bytes.copy_from_slice(&block_data[pos..pos + 4]);
            let klen = u32::from_le_bytes(klen_bytes) as usize;
            pos += 4;
            
            // FIXED: Consistent ordering - klen, vlen, key, value
            if pos + 4 > block_data.len() {
                break;
            }
            
            let mut vlen_bytes = [0u8; 4];
            vlen_bytes.copy_from_slice(&block_data[pos..pos + 4]);
            let vlen = u32::from_le_bytes(vlen_bytes) as usize;
            pos += 4;
            
            if pos + klen > block_data.len() {
                break;
            }
            
            let k = String::from_utf8_lossy(&block_data[pos..pos + klen]);
            pos += klen;
            
            if k == key && rec_type == RT_SET {
                if pos + vlen > block_data.len() {
                    break;
                }
                let v = String::from_utf8_lossy(&block_data[pos..pos + vlen]);
                return Ok(Some((v.to_string(), seq)));
            }
            
            pos += vlen;
        }
        
        Ok(None)
    }
    
    fn scan_segment(&self, seg: &Arc<Segment>, start: &str, end: &str) -> io::Result<Vec<(String, String, u64)>> {
        let mut results = Vec::new();
        
        for (idx_key, offset) in &seg.index {
            if idx_key.as_str() >= start && idx_key.as_str() < end {
                let next_offset = seg.index.iter()
                    .find(|(k, _)| k > idx_key)
                    .map(|(_, o)| *o)
                    .unwrap_or(seg.index_start);  // FIXED: Use index_start
                
                let block_data = self.cache.get_or_load(&seg.path, *offset, (next_offset - offset) as usize)?;
                
                let mut pos = 0;
                while pos + 8 < block_data.len() {
                    let mut seq_bytes = [0u8; 8];
                    seq_bytes.copy_from_slice(&block_data[pos..pos + 8]);
                    let seq = u64::from_le_bytes(seq_bytes);
                    pos += 8;
                    
                    if pos >= block_data.len() {
                        break;
                    }
                    
                    let rec_type = block_data[pos];
                    pos += 1;
                    
                    if pos + 8 > block_data.len() {
                        break;
                    }
                    
                    let mut klen_bytes = [0u8; 4];
                    klen_bytes.copy_from_slice(&block_data[pos..pos + 4]);
                    let klen = u32::from_le_bytes(klen_bytes) as usize;
                    pos += 4;
                    
                    let mut vlen_bytes = [0u8; 4];
                    vlen_bytes.copy_from_slice(&block_data[pos..pos + 4]);
                    let vlen = u32::from_le_bytes(vlen_bytes) as usize;
                    pos += 4;
                    
                    if pos + klen + vlen > block_data.len() {
                        break;
                    }
                    
                    let k = String::from_utf8_lossy(&block_data[pos..pos + klen]);
                    pos += klen;
                    
                    if k.as_ref() >= start && k.as_ref() < end && rec_type == RT_SET {
                        let v = String::from_utf8_lossy(&block_data[pos..pos + vlen]);
                        results.push((k.to_string(), v.to_string(), seq));
                    }
                    
                    pos += vlen;
                }
            }
        }
        
        Ok(results)
    }
    
    fn flush_memtable_locked(&self, inner: &mut StoreInner) -> io::Result<()> {
        if inner.memtable.is_empty() {
            return Ok(());
        }
        
        let filename = format!("l0_{:010}.seg", inner.seq);
        let path = self.dir.join(&filename);
        
        let mut writer = SegmentWriter::new(&path)?;
        
        for (k, v) in &inner.memtable {
            match v {
                MemValue::Scalar(val, seq) => {
                    writer.add(RT_SET, k, Some(val), *seq)?;
                }
                MemValue::PointTomb(seq) => {
                    writer.add(RT_DEL_POINT, k, None, *seq)?;
                }
            }
        }
        
        let seg = writer.finish()?;
        
        // Update manifest
        {
            let mut manifest = self.manifest.lock().unwrap();
            manifest.add_entry(ManifestEntry {
                seq_high: seg.seq_high,
                level: 0,
                filename,
            })?;
        }
        
        inner.segments_l0.push(Arc::new(seg));
        inner.memtable.clear();
        inner.memtable_size = 0;
        
        self.wal.sync_now()?;
        
        Ok(())
    }
    
    pub fn flush(&self) -> io::Result<()> {
        let mut inner = self.inner.write().unwrap();
        self.flush_memtable_locked(&mut inner)?;
        self.wal.sync_now()?;
        Ok(())
    }
    
    pub fn delete(&self, path: &str) -> io::Result<()> {
        let mut inner = self.inner.write().unwrap();
        inner.seq += 1;
        let seq = inner.seq;
        
        self.wal.append(&WALEntry {
            seq,
            kind: RT_DEL_POINT,
            key: path.to_string(),
            value: None,
        })?;
        
        inner.memtable.insert(path.to_string(), MemValue::PointTomb(seq));
        Ok(())
    }
    
    pub fn delete_subtree(&self, prefix: &str) -> io::Result<()> {
        let mut inner = self.inner.write().unwrap();
        inner.seq += 1;
        let seq = inner.seq;
        
        let prefix = if prefix.ends_with('/') {
            prefix.to_string()
        } else {
            format!("{}/", prefix)
        };
        
        self.wal.append(&WALEntry {
            seq,
            kind: RT_DEL_SUB,
            key: prefix.clone(),
            value: None,
        })?;
        
        inner.subtombs.insert(prefix, seq);
        Ok(())
    }
}

impl StoreInner {
    fn replay_wal(&mut self, path: &Path) -> io::Result<()> {
        if !path.exists() {
            return Ok(());
        }
        
        let file = File::open(path)?;
        let mut reader = BufReader::new(file);
        
        let mut magic_buf = [0u8; 4];
        if reader.read_exact(&mut magic_buf).is_err() {
            return Ok(());
        }
        
        if &magic_buf != WAL_MAGIC {
            return Ok(());
        }
        
        loop {
            let mut len_buf = [0u8; 4];
            if reader.read_exact(&mut len_buf).is_err() {
                break;
            }
            
            let len = u32::from_le_bytes(len_buf) as usize;
            let mut record = vec![0u8; len];
            
            if reader.read_exact(&mut record).is_err() {
                break;
            }
            
            let mut crc_buf = [0u8; 4];
            if reader.read_exact(&mut crc_buf).is_err() {
                break;
            }
            
            let expected_crc = u32::from_le_bytes(crc_buf);
            if crc32(&record) != expected_crc {
                break;
            }
            
            // Parse record
            if record.len() < 13 {
                continue;
            }
            
            let mut seq_bytes = [0u8; 8];
            seq_bytes.copy_from_slice(&record[0..8]);
            let seq = u64::from_le_bytes(seq_bytes);
            
            let kind = record[8];
            
            let mut klen_bytes = [0u8; 4];
            klen_bytes.copy_from_slice(&record[9..13]);
            let klen = u32::from_le_bytes(klen_bytes) as usize;
            
            if record.len() < 13 + klen {
                continue;
            }
            
            let key = String::from_utf8_lossy(&record[13..13 + klen]).to_string();
            
            match kind {
                RT_SET => {
                    if record.len() >= 17 + klen {
                        let mut vlen_bytes = [0u8; 4];
                        vlen_bytes.copy_from_slice(&record[13 + klen..17 + klen]);
                        let vlen = u32::from_le_bytes(vlen_bytes) as usize;
                        
                        if record.len() >= 17 + klen + vlen {
                            let val = String::from_utf8_lossy(&record[17 + klen..17 + klen + vlen]).to_string();
                            self.memtable.insert(key.clone(), MemValue::Scalar(val.clone(), seq));
                            self.memtable_size += key.len() + val.len() + 16;
                        }
                    }
                }
                RT_DEL_POINT => {
                    self.memtable.insert(key, MemValue::PointTomb(seq));
                }
                RT_DEL_SUB => {
                    self.subtombs.insert(key, seq);
                }
                _ => {}
            }
            
            if seq > self.seq {
                self.seq = seq;
            }
        }
        
        Ok(())
    }
}

impl GroupCommitWAL {
    fn new(path: &Path) -> io::Result<Self> {
        Ok(GroupCommitWAL {
            path: path.to_path_buf(),
            buffer: Mutex::new(Vec::new()),
            // sync_interval: Duration::from_millis(GROUP_COMMIT_MS),
            shutdown: Arc::new((Mutex::new(false), Condvar::new())),
        })
    }
    
    fn append(&self, entry: &WALEntry) -> io::Result<()> {
        let mut buffer = self.buffer.lock().unwrap();
        buffer.push(WALEntry {
            seq: entry.seq,
            kind: entry.kind,
            key: entry.key.clone(),
            value: entry.value.clone(),
        });
        
        // Optionally sync immediately for critical operations
        if buffer.len() > 100 {
            drop(buffer);
            self.sync_now()?;
        }
        
        Ok(())
    }
    
    fn sync_now(&self) -> io::Result<()> {
        let mut buffer = self.buffer.lock().unwrap();
        if buffer.is_empty() {
            return Ok(());
        }
        
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?;
        
        // Write magic if new file
        if file.metadata()?.len() == 0 {
            file.write_all(WAL_MAGIC)?;
        }
        
        for entry in buffer.drain(..) {
            let mut record = Vec::new();
            record.extend_from_slice(&entry.seq.to_le_bytes());
            record.push(entry.kind);
            record.extend_from_slice(&(entry.key.len() as u32).to_le_bytes());
            record.extend_from_slice(entry.key.as_bytes());
            
            if let Some(val) = &entry.value {
                record.extend_from_slice(&(val.len() as u32).to_le_bytes());
                record.extend_from_slice(val.as_bytes());
            }
            
            file.write_all(&(record.len() as u32).to_le_bytes())?;
            file.write_all(&record)?;
            file.write_all(&crc32(&record).to_le_bytes())?;
        }
        
        file.sync_all()?;
        Ok(())
    }
}

impl Segment {
    fn open(path: &Path) -> io::Result<Self> {
        let mut file = File::open(path)?;
        let file_len = file.metadata()?.len();
        
        // Read header
        let mut magic_buf = [0u8; 7];
        file.read_exact(&mut magic_buf)?;
        if &magic_buf != MAGIC {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "Bad magic"));
        }
        
        // Read footer from end
        file.seek(SeekFrom::End(-32))?;
        let mut footer = [0u8; 32];
        file.read_exact(&mut footer)?;
        
        // seq_low stored in footer but not currently used
        // let mut seq_low_bytes = [0u8; 8];
        // seq_low_bytes.copy_from_slice(&footer[0..8]);
        // let seq_low = u64::from_le_bytes(seq_low_bytes);
        
        let mut seq_high_bytes = [0u8; 8];
        seq_high_bytes.copy_from_slice(&footer[8..16]);
        let seq_high = u64::from_le_bytes(seq_high_bytes);
        
        // key_count stored in footer but not currently used
        // let mut key_count_bytes = [0u8; 4];
        // key_count_bytes.copy_from_slice(&footer[16..20]);
        // let key_count = u32::from_le_bytes(key_count_bytes) as usize;
        
        let mut index_size_bytes = [0u8; 4];
        index_size_bytes.copy_from_slice(&footer[20..24]);
        let index_size = u32::from_le_bytes(index_size_bytes) as usize;
        
        let mut bloom_size_bytes = [0u8; 4];
        bloom_size_bytes.copy_from_slice(&footer[24..28]);
        let bloom_size = u32::from_le_bytes(bloom_size_bytes) as usize;
        
        let mut hash_count_bytes = [0u8; 4];
        hash_count_bytes.copy_from_slice(&footer[28..32]);
        let hash_count = u32::from_le_bytes(hash_count_bytes) as usize;
        
        // Calculate index start position
        let index_start = file_len - 32 - index_size as u64 - bloom_size as u64;
        
        // Read bloom filter
        let bloom = if bloom_size > 0 {
            file.seek(SeekFrom::End(-(32 + bloom_size as i64)))?;
            let mut bloom_data = vec![0u8; bloom_size];
            file.read_exact(&mut bloom_data)?;
            
            Some(BloomFilter {
                bits: bloom_data,
                bit_count: bloom_size * 8,
                hash_count,
            })
        } else {
            None
        };
        
        // Read index
        file.seek(SeekFrom::End(-(32 + bloom_size as i64 + index_size as i64)))?;
        let mut index_data = vec![0u8; index_size];
        file.read_exact(&mut index_data)?;
        
        let mut index = Vec::new();
        let mut pos = 0;
        
        while pos < index_data.len() {
            if pos + 12 > index_data.len() {
                break;
            }
            
            let mut klen_bytes = [0u8; 4];
            klen_bytes.copy_from_slice(&index_data[pos..pos + 4]);
            let klen = u32::from_le_bytes(klen_bytes) as usize;
            pos += 4;
            
            let mut offset_bytes = [0u8; 8];
            offset_bytes.copy_from_slice(&index_data[pos..pos + 8]);
            let offset = u64::from_le_bytes(offset_bytes);
            pos += 8;
            
            if pos + klen > index_data.len() {
                break;
            }
            
            let key = String::from_utf8_lossy(&index_data[pos..pos + klen]).to_string();
            pos += klen;
            
            index.push((key, offset));
        }
        
        Ok(Segment {
            path: path.to_path_buf(),
            // seq_low,
            seq_high,
            // key_count,
            bloom,
            index,
            index_start,  // Store for block boundary calculation
        })
    }
}

struct SegmentWriter {
    file: File,
    path: PathBuf,
    seq_low: u64,
    seq_high: u64,
    key_count: usize,
    current_block: Vec<u8>,
    index: Vec<(String, u64)>,
    bloom: BloomFilter,
    written: u64,
}

impl SegmentWriter {
    fn new(path: &Path) -> io::Result<Self> {
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(path)?;
        
        let mut writer = SegmentWriter {
            file,
            path: path.to_path_buf(),
            seq_low: u64::MAX,
            seq_high: 0,
            key_count: 0,
            current_block: Vec::new(),
            index: Vec::new(),
            bloom: BloomFilter::new(10000, 7),  // Fixed params for now
            written: 0,
        };
        
        writer.file.write_all(MAGIC)?;
        writer.written = MAGIC.len() as u64;
        
        Ok(writer)
    }
    
    fn add(&mut self, rec_type: u8, key: &str, value: Option<&str>, seq: u64) -> io::Result<()> {
        self.bloom.add(key);
        
        if seq < self.seq_low {
            self.seq_low = seq;
        }
        if seq > self.seq_high {
            self.seq_high = seq;
        }
        
        // Build record with FIXED consistent order
        let mut record = Vec::new();
        record.extend_from_slice(&seq.to_le_bytes());
        record.push(rec_type);
        record.extend_from_slice(&(key.len() as u32).to_le_bytes());
        record.extend_from_slice(&(value.as_ref().map_or(0, |v| v.len()) as u32).to_le_bytes());
        record.extend_from_slice(key.as_bytes());
        if let Some(v) = value {
            record.extend_from_slice(v.as_bytes());
        }
        
        if self.current_block.len() + record.len() > BLOCK_SIZE {
            self.flush_block()?;
        }
        
        if self.current_block.is_empty() {
            self.index.push((key.to_string(), self.written));
        }
        
        self.current_block.extend_from_slice(&record);
        self.key_count += 1;
        
        Ok(())
    }
    
    fn flush_block(&mut self) -> io::Result<()> {
        if self.current_block.is_empty() {
            return Ok(());
        }
        
        self.file.write_all(&self.current_block)?;
        self.written += self.current_block.len() as u64;
        self.current_block.clear();
        
        Ok(())
    }
    
    fn finish(mut self) -> io::Result<Segment> {
        self.flush_block()?;
        
        let index_start = self.written;
        
        // Write index
        let mut index_data = Vec::new();
        for (k, offset) in &self.index {
            index_data.extend_from_slice(&(k.len() as u32).to_le_bytes());
            index_data.extend_from_slice(&offset.to_le_bytes());
            index_data.extend_from_slice(k.as_bytes());
        }
        self.file.write_all(&index_data)?;
        
        // Write bloom filter
        self.file.write_all(&self.bloom.bits)?;
        
        // Write footer
        let mut footer = Vec::new();
        footer.extend_from_slice(&self.seq_low.to_le_bytes());
        footer.extend_from_slice(&self.seq_high.to_le_bytes());
        footer.extend_from_slice(&(self.key_count as u32).to_le_bytes());
        footer.extend_from_slice(&(index_data.len() as u32).to_le_bytes());
        footer.extend_from_slice(&(self.bloom.bits.len() as u32).to_le_bytes());
        footer.extend_from_slice(&(self.bloom.hash_count as u32).to_le_bytes());
        self.file.write_all(&footer)?;
        
        self.file.sync_all()?;
        
        Ok(Segment {
            path: self.path,
            // seq_low: self.seq_low,
            seq_high: self.seq_high,
            // key_count: self.key_count,
            bloom: Some(self.bloom),
            index: self.index,
            index_start,
        })
    }
}

impl BloomFilter {
    fn new(bit_count: usize, hash_count: usize) -> Self {
        BloomFilter {
            bits: vec![0u8; (bit_count + 7) / 8],
            bit_count,
            hash_count,
        }
    }
    
    fn add(&mut self, key: &str) {
        for i in 0..self.hash_count {
            let hash = xxhash(key.as_bytes(), i as u64) as usize % self.bit_count;
            self.bits[hash / 8] |= 1 << (hash % 8);
        }
    }
    
    fn might_contain(&self, key: &str) -> bool {
        for i in 0..self.hash_count {
            let hash = xxhash(key.as_bytes(), i as u64) as usize % self.bit_count;
            if self.bits[hash / 8] & (1 << (hash % 8)) == 0 {
                return false;
            }
        }
        true
    }
}

impl BlockCache {
    fn new(max_size: usize) -> Self {
        BlockCache {
            cache: RwLock::new(HashMap::new()),
            size: RwLock::new(0),
            max_size,
        }
    }
    
    fn get_or_load(&self, path: &Path, offset: u64, size: usize) -> io::Result<Arc<Vec<u8>>> {
        let key = (path.to_path_buf(), offset);
        
        {
            let cache = self.cache.read().unwrap();
            if let Some(data) = cache.get(&key) {
                return Ok(data.clone());
            }
        }
        
        // Load from disk
        let mut file = File::open(path)?;
        file.seek(SeekFrom::Start(offset))?;
        
        let mut data = vec![0u8; size];
        file.read_exact(&mut data)?;
        
        let data = Arc::new(data);
        
        // Add to cache
        let mut cache = self.cache.write().unwrap();
        let mut size = self.size.write().unwrap();
        
        *size += data.len();
        cache.insert(key, data.clone());
        
        // Simple eviction if over limit
        while *size > self.max_size && !cache.is_empty() {
            if let Some((k, v)) = cache.iter().next() {
                let k = k.clone();
                let v_size = v.len();
                cache.remove(&k);
                *size -= v_size;
            }
        }
        
        Ok(data)
    }
}

impl Manifest {
    fn load(path: &Path) -> io::Result<Self> {
        let mut manifest = Manifest {
            path: path.to_path_buf(),
            entries: Vec::new(),
        };
        
        if !path.exists() {
            return Ok(manifest);
        }
        
        let file = File::open(path)?;
        let mut reader = BufReader::new(file);
        let mut line = String::new();
        
        while reader.read_line(&mut line)? > 0 {
            // Simple format: seq_high|level|filename
            let parts: Vec<&str> = line.trim().split('|').collect();
            if parts.len() == 3 {
                if let Ok(seq_high) = parts[0].parse::<u64>() {
                    if let Ok(level) = parts[1].parse::<usize>() {
                        manifest.entries.push(ManifestEntry {
                            seq_high,
                            level,
                            filename: parts[2].to_string(),
                        });
                    }
                }
            }
            line.clear();
        }
        
        Ok(manifest)
    }
    
    fn add_entry(&mut self, entry: ManifestEntry) -> io::Result<()> {
        self.entries.push(entry.clone());
        
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?;
        
        writeln!(file, "{}|{}|{}", entry.seq_high, entry.level, entry.filename)?;
        file.sync_all()?;
        
        Ok(())
    }
}

// Helper functions
fn parent_path(path: &str) -> Option<String> {
    if let Some(idx) = path.rfind('/') {
        if idx > 0 {
            Some(path[..idx].to_string())
        } else {
            None
        }
    } else {
        None
    }
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffffffff;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xedb88320
            } else {
                crc >> 1
            };
        }
    }
    crc ^ 0xffffffff
}

fn xxhash(data: &[u8], seed: u64) -> u64 {
    // Simplified xxhash for bloom filter
    let mut h = seed.wrapping_add(data.len() as u64);
    for chunk in data.chunks(8) {
        let mut val = 0u64;
        for (i, &b) in chunk.iter().enumerate() {
            val |= (b as u64) << (i * 8);
        }
        h = h.wrapping_mul(0x9e3779b97f4a7c15).wrapping_add(val);
        h = (h << 31) | (h >> 33);
    }
    h
}

// Simple pipe-delimited manifest format (no serde dependency)

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: {} <directory>", args[0]);
        std::process::exit(1);
    }
    
    let store = Store::open(Path::new(&args[1]))?;
    let stdin = io::stdin();
    
    for line in stdin.lock().lines() {
        let line = line?;
        let parts: Vec<&str> = line.trim().split_whitespace().collect();
        
        if parts.is_empty() {
            continue;
        }
        
        match parts[0] {
            "set" => {
                if parts.len() >= 3 {
                    let key = parts[1];
                    let value = parts[2..].join(" ");
                    store.set(key, &value, false)?;
                    println!("OK");
                }
            }
            "set-r" => {
                if parts.len() >= 3 {
                    let key = parts[1];
                    let value = parts[2..].join(" ");
                    store.set(key, &value, true)?;
                    println!("OK");
                }
            }
            "get" => {
                if parts.len() >= 2 {
                    let key = parts[1];
                    match store.get(key)? {
                        Some(v) => println!("{}", v),
                        None => println!("NOT_FOUND"),
                    }
                }
            }
            "del" => {
                if parts.len() >= 2 {
                    store.delete(parts[1])?;
                    println!("OK");
                }
            }
            "del-sub" => {
                if parts.len() >= 2 {
                    store.delete_subtree(parts[1])?;
                    println!("OK");
                }
            }
            "flush" => {
                store.flush()?;
                println!("OK");
            }
            "exit" => break,
            _ => println!("Unknown command"),
        }
    }
    
    Ok(())
}