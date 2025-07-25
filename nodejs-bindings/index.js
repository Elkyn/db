const binding = require('./build/Release/elkyn_store');
const { Observable } = require('./src/observable');
const { pack, unpack } = require('msgpackr');

class ElkynStore {
    constructor(options) {
        // Handle both old API and new options
        if (typeof options === 'string') {
            // Legacy: new ElkynStore('./data')
            this.handle = binding.init(options);
            this.dataDir = options;
            this.mode = 'standalone';
        } else {
            // New API: new ElkynStore({ mode: 'standalone', dataDir: './data' })
            const { mode = 'standalone', dataDir = './data', clusterUrl } = options || {};
            this.mode = mode;
            this.dataDir = dataDir;
            this.clusterUrl = clusterUrl;
            
            if (mode === 'standalone') {
                this.handle = binding.init(dataDir);
            } else if (mode === 'embedded') {
                // TODO: Implement cluster connection
                this.handle = binding.init(dataDir);
            } else {
                throw new Error(`Unknown mode: ${mode}`);
            }
        }
        
        this._observables = new Map();
        this._eventQueueEnabled = false;
    }

    /**
     * Enable JWT authentication
     * @param {string} secret - JWT secret key
     * @returns {boolean} success
     */
    enableAuth(secret) {
        const result = binding.enableAuth(this.handle, secret);
        return result === 0;
    }

    /**
     * Enable security rules
     * @param {string|object} rules - Rules JSON string or object
     * @returns {boolean} success
     */
    enableRules(rules) {
        const rulesStr = typeof rules === 'string' ? rules : JSON.stringify(rules);
        const result = binding.enableRules(this.handle, rulesStr);
        return result === 0;
    }

    /**
     * Set a string value at path
     * @param {string} path - Data path (e.g., '/users/123/name')
     * @param {string} value - String value to set
     * @param {string} [token] - Optional JWT token for auth
     * @returns {boolean} success
     */
    setString(path, value, token = null) {
        const result = binding.setString(this.handle, path, value, token);
        if (result === -2) {
            throw new Error('Authentication failed');
        }
        if (result === -1) {
            throw new Error('Access denied or operation failed');
        }
        return result === 0;
    }

    /**
     * Get a string value from path
     * @param {string} path - Data path
     * @param {string} [token] - Optional JWT token for auth
     * @returns {string|null} value or null if not found
     */
    getString(path, token = null) {
        try {
            return binding.getString(this.handle, path, token);
        } catch (error) {
            if (error.message.includes('Access denied')) {
                throw new Error('Access denied');
            }
            return null;
        }
    }

    /**
     * Delete value at path
     * @param {string} path - Data path
     * @param {string} [token] - Optional JWT token for auth
     * @returns {boolean} success
     */
    delete(path, token = null) {
        const result = binding.delete(this.handle, path, token);
        if (result === -2) {
            throw new Error('Authentication failed');
        }
        if (result === -1) {
            throw new Error('Access denied or path not found');
        }
        return result === 0;
    }

    /**
     * Create JWT token (for development/testing)
     * @param {string} uid - User ID
     * @param {string} [email] - User email
     * @returns {string} JWT token
     */
    createToken(uid, email = null) {
        const token = binding.createToken(this.handle, uid, email);
        if (!token) {
            throw new Error('Failed to create token - auth not enabled?');
        }
        return token;
    }

    /**
     * Close the database connection
     */
    close() {
        if (this.handle) {
            binding.close(this.handle);
            this.handle = null;
        }
    }
    
    /**
     * Enable write queue for async operations
     * @returns {boolean} success
     */
    enableWriteQueue() {
        const result = binding.enableWriteQueue(this.handle);
        return result === 0;
    }
    
    /**
     * Set data asynchronously
     * @param {string} path - Data path
     * @param {any} value - Value to store
     * @param {string} [token] - Optional JWT token for auth
     * @returns {string} Write ID for tracking
     */
    setAsync(path, value, token = null) {
        const packed = pack(value);
        const id = binding.setBinaryAsync(this.handle, path, packed, token);
        if (!id || id === "0") {
            throw new Error('Failed to queue write operation');
        }
        return id;
    }
    
    /**
     * Delete data asynchronously
     * @param {string} path - Data path
     * @param {string} [token] - Optional JWT token for auth
     * @returns {string} Write ID for tracking
     */
    deleteAsync(path, token = null) {
        const id = binding.deleteAsync(this.handle, path, token);
        if (!id || id === "0") {
            throw new Error('Failed to queue delete operation');
        }
        return id;
    }
    
    /**
     * Wait for async write to complete
     * @param {string} writeId - Write ID from setAsync/deleteAsync
     * @returns {Promise<void>}
     */
    async waitForWrite(writeId) {
        return new Promise((resolve, reject) => {
            // Use setImmediate to avoid blocking
            setImmediate(() => {
                const result = binding.waitForWrite(this.handle, writeId);
                if (result === 0) {
                    resolve();
                } else {
                    reject(new Error('Write operation failed'));
                }
            });
        });
    }

    /**
     * Set a MessagePack value at path
     * @param {string} path - Data path
     * @param {any} value - Value to serialize and store
     * @param {string} [token] - Optional JWT token for auth
     * @returns {boolean} success
     */
    set(path, value, token = null) {
        const binaryData = pack(value);
        return this.setBinary(path, binaryData, token);
    }

    /**
     * Get raw value (zero-copy for primitives)
     * @param {string} path - Data path
     * @param {string} [token] - Optional JWT token for auth
     * @returns {any} Value or null
     */
    getRaw(path, token = null) {
        const result = binding.getRaw(this.handle, path, token);
        
        // If it's a Buffer (complex type), unpack it
        if (Buffer.isBuffer(result)) {
            try {
                return unpack(result);
            } catch (error) {
                return null;
            }
        }
        
        return result;
    }
    
    /**
     * Get and parse MessagePack value from path
     * @param {string} path - Data path
     * @param {string} [token] - Optional JWT token for auth
     * @returns {any} parsed value or null
     */
    get(path, token = null) {
        // Use zero-copy getRaw for better performance
        return this.getRaw(path, token);
    }

    /**
     * Set binary MessagePack data at path
     * @param {string} path - Data path
     * @param {Buffer} binaryData - MessagePack binary data
     * @param {string} [token] - Optional JWT token for auth
     * @returns {boolean} success
     */
    setBinary(path, binaryData, token = null) {
        const result = binding.setBinary(this.handle, path, binaryData, token);
        if (result === -2) {
            throw new Error('Authentication failed');
        }
        if (result === -1) {
            throw new Error('Access denied or operation failed');
        }
        return result === 0;
    }

    /**
     * Get binary MessagePack data from path
     * @param {string} path - Data path
     * @param {string} [token] - Optional JWT token for auth
     * @returns {Buffer|null} binary data or null if not found
     */
    getBinary(path, token = null) {
        try {
            return binding.getBinary(this.handle, path, token);
        } catch (error) {
            if (error.message.includes('Access denied')) {
                throw new Error('Access denied');
            }
            return null;
        }
    }

    /**
     * Setup default Firebase-style rules
     * @returns {boolean} success
     */
    setupDefaultRules() {
        const defaultRules = {
            rules: {
                users: {
                    "$userId": {
                        ".read": "$userId === auth.uid",
                        ".write": "$userId === auth.uid",
                        "name": {
                            ".read": "true"
                        }
                    }
                }
            }
        };
        
        return this.enableRules(defaultRules);
    }

    /**
     * Watch a path for changes (Observable pattern)
     * @param {string} path - Path to watch (supports wildcards)
     * @returns {Observable} Observable that emits events
     * 
     * @example
     * // Watch specific path
     * store.watch('/users/123').subscribe(event => {
     *   console.log(event.type, event.path, event.value);
     * });
     * 
     * // Watch with wildcards
     * store.watch('/users/*').subscribe(event => {
     *   console.log('User changed:', event.path);
     * });
     * 
     * // Use async iterator
     * for await (const event of store.watch('/products/*')) {
     *   console.log('Product update:', event);
     * }
     */
    watch(path) {
        if (!this._observables.has(path)) {
            this._observables.set(path, new Observable(this, path));
        }
        return this._observables.get(path);
    }

    /**
     * Internal method for native watch binding
     * @private
     */
    _watchNative(path, callback) {
        // Enable event queue on first watch
        if (!this._eventQueueEnabled) {
            binding.enableEventQueue(this.handle);
            this._eventQueueEnabled = true;
        }
        
        return binding.watch(this.handle, path, callback);
    }

    /**
     * Internal method for native unwatch binding
     * @private
     */
    _unwatchNative(subscriptionId) {
        binding.unwatch(this.handle, subscriptionId);
    }
}

module.exports = { ElkynStore };