const binding = require('./build/Release/elkyn_store');
const { Observable } = require('./src/observable');

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
     * Set a JSON value at path
     * @param {string} path - Data path
     * @param {any} value - Value to serialize and store
     * @param {string} [token] - Optional JWT token for auth
     * @returns {boolean} success
     */
    set(path, value, token = null) {
        return this.setString(path, JSON.stringify(value), token);
    }

    /**
     * Get and parse JSON value from path
     * @param {string} path - Data path
     * @param {string} [token] - Optional JWT token for auth
     * @returns {any} parsed value or null
     */
    get(path, token = null) {
        const str = this.getString(path, token);
        if (str === null) return null;
        
        try {
            return JSON.parse(str);
        } catch (error) {
            // Return as string if not valid JSON
            return str;
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