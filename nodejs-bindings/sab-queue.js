/**
 * ArrayBuffer-based operation queue for reduced N-API overhead
 * This allows JavaScript to write operations directly to shared memory
 * that Zig can consume with minimal N-API calls!
 */

const OP_SET = 1;
const OP_DELETE = 2;
const OP_SHUTDOWN = 255;

const HEADER_SIZE = 48; // Must match Zig OperationHeader size

class SABQueue {
    constructor(arrayBuffer) {
        this.sab = arrayBuffer;
        this.view = new DataView(arrayBuffer);
        this.buffer = new Uint8Array(arrayBuffer);
        this.int32View = new Int32Array(arrayBuffer, 0, 2); // First 8 bytes for head/tail
        
        // Layout: [head:4][tail:4][data:remaining]
        this.headOffset = 0;
        this.tailOffset = 4;
        this.dataOffset = 8;
        this.dataSize = arrayBuffer.byteLength - 8;
        
        // Current data position for writing values
        this.currentDataPos = this.dataOffset;
        this.sequenceNumber = 0;
    }
    
    /**
     * Write a SET operation to the queue
     * @param {string} path - Database path
     * @param {any} value - Value to store
     * @returns {boolean} Success
     */
    enqueueSet(path, value) {
        const pathBytes = new TextEncoder().encode(path);
        const valueBytes = this.encodeValue(value);
        
        return this.enqueueOperation(OP_SET, pathBytes, valueBytes);
    }
    
    /**
     * Write a DELETE operation to the queue
     * @param {string} path - Database path
     * @returns {boolean} Success
     */
    enqueueDelete(path) {
        const pathBytes = new TextEncoder().encode(path);
        
        return this.enqueueOperation(OP_DELETE, pathBytes, null);
    }
    
    /**
     * Encode JavaScript value to binary format that Zig can understand
     */
    encodeValue(value) {
        if (typeof value === 'string') {
            // 's' + string bytes
            const strBytes = new TextEncoder().encode(value);
            const result = new Uint8Array(1 + strBytes.length);
            result[0] = 115; // 's'
            result.set(strBytes, 1);
            return result;
        }
        
        if (typeof value === 'number') {
            // 'n' + 8 bytes for f64
            const result = new Uint8Array(9);
            result[0] = 110; // 'n'
            const view = new DataView(result.buffer);
            view.setFloat64(1, value, true); // little endian
            return result;
        }
        
        if (typeof value === 'boolean') {
            // 'b' + 1 byte
            const result = new Uint8Array(2);
            result[0] = 98; // 'b'
            result[1] = value ? 1 : 0;
            return result;
        }
        
        if (value === null || value === undefined) {
            // 'z' for null
            return new Uint8Array([122]); // 'z'
        }
        
        // For complex objects, encode as JSON
        // 'j' + JSON string bytes
        const jsonStr = JSON.stringify(value);
        const jsonBytes = new TextEncoder().encode(jsonStr);
        const result = new Uint8Array(1 + jsonBytes.length);
        result[0] = 106; // 'j'
        result.set(jsonBytes, 1);
        return result;
    }
    
    /**
     * Low-level operation enqueue
     */
    enqueueOperation(opType, pathBytes, valueBytes) {
        const valueLength = valueBytes ? valueBytes.length : 0;
        const totalSize = HEADER_SIZE + pathBytes.length + valueLength;
        
        // Check if we have space (simple check, doesn't handle wrap-around perfectly)
        const currentTail = this.int32View[this.tailOffset / 4];
        const currentHead = this.int32View[this.headOffset / 4];
        
        const available = this.dataSize - (currentTail - currentHead);
        if (totalSize > available) {
            console.warn('SAB queue full, dropping operation');
            return false;
        }
        
        // Calculate positions
        const headerPos = currentTail;
        const pathPos = this.allocateData(pathBytes.length);
        const valuePos = valueBytes ? this.allocateData(valueLength) : 0;
        
        // Write path data
        this.buffer.set(pathBytes, pathPos);
        
        // Write value data
        if (valueBytes) {
            this.buffer.set(valueBytes, valuePos);
        }
        
        // Write operation header
        this.writeHeader(headerPos, opType, pathPos, pathBytes.length, valuePos, valueLength);
        
        // Update tail pointer
        const newTail = (currentTail + HEADER_SIZE) % this.dataSize;
        this.int32View[this.tailOffset / 4] = newTail;
        
        return true;
    }
    
    /**
     * Allocate space in data section
     */
    allocateData(size) {
        const pos = this.currentDataPos;
        this.currentDataPos += size;
        
        // Simple wrap-around (not perfect, but good enough for demo)
        if (this.currentDataPos >= this.dataOffset + this.dataSize) {
            this.currentDataPos = this.dataOffset + 1024; // Leave some space after headers
        }
        
        return pos;
    }
    
    /**
     * Write operation header to specific position
     */
    writeHeader(pos, opType, pathOffset, pathLength, valueOffset, valueLength) {
        const headerView = new DataView(this.sab, pos, HEADER_SIZE);
        
        headerView.setUint32(0, opType, true);           // op_type (4 bytes)
        headerView.setUint32(4, pathOffset, true);       // path_offset (4 bytes)
        headerView.setUint32(8, pathLength, true);       // path_length (4 bytes)
        headerView.setUint32(12, valueOffset, true);     // value_offset (4 bytes)
        headerView.setUint32(16, valueLength, true);     // value_length (4 bytes)
        headerView.setBigUint64(20, BigInt(this.sequenceNumber++), true); // sequence (8 bytes)
        headerView.setBigUint64(28, 0n, true);           // reserved (8 bytes)
        // Total: 4+4+4+4+4+8+8 = 36 bytes, we need 12 more bytes for 48 total
        headerView.setUint32(36, 0, true);               // padding
        headerView.setUint32(40, 0, true);               // padding
        headerView.setUint32(44, 0, true);               // padding (total now 48 bytes)
    }
    
    /**
     * Get queue statistics
     */
    getStats() {
        const head = this.int32View[this.headOffset / 4];
        const tail = this.int32View[this.tailOffset / 4];
        
        const pending = tail >= head ? tail - head : this.dataSize - head + tail;
        
        return {
            head,
            tail,
            pending: Math.floor(pending / HEADER_SIZE),
            bufferSize: this.dataSize
        };
    }
    
    /**
     * Signal shutdown to worker thread
     */
    shutdown() {
        return this.enqueueOperation(OP_SHUTDOWN, new Uint8Array([]), null);
    }
}

module.exports = { SABQueue, OP_SET, OP_DELETE, OP_SHUTDOWN };