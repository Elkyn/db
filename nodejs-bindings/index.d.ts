export interface ElkynStoreOptions {
    dataDir: string;
}

export interface SecurityRules {
    rules: {
        [path: string]: any;
    };
}

export declare class ElkynStore {
    constructor(dataDir: string);

    /**
     * Enable JWT authentication
     * @param secret JWT secret key
     * @returns success
     */
    enableAuth(secret: string): boolean;

    /**
     * Enable security rules
     * @param rules Rules JSON string or object
     * @returns success
     */
    enableRules(rules: string | SecurityRules): boolean;

    /**
     * Set a string value at path
     * @param path Data path (e.g., '/users/123/name')
     * @param value String value to set
     * @param token Optional JWT token for auth
     * @returns success
     * @throws Error if authentication fails or access denied
     */
    setString(path: string, value: string, token?: string | null): boolean;

    /**
     * Get a string value from path
     * @param path Data path
     * @param token Optional JWT token for auth
     * @returns value or null if not found
     * @throws Error if access denied
     */
    getString(path: string, token?: string | null): string | null;

    /**
     * Delete value at path
     * @param path Data path
     * @param token Optional JWT token for auth
     * @returns success
     * @throws Error if authentication fails or access denied
     */
    delete(path: string, token?: string | null): boolean;

    /**
     * Create JWT token (for development/testing)
     * @param uid User ID
     * @param email User email
     * @returns JWT token
     * @throws Error if token creation fails
     */
    createToken(uid: string, email?: string | null): string;

    /**
     * Close the database connection
     */
    close(): void;

    /**
     * Set a JSON value at path
     * @param path Data path
     * @param value Value to serialize and store
     * @param token Optional JWT token for auth
     * @returns success
     * @throws Error if authentication fails or access denied
     */
    set(path: string, value: any, token?: string | null): boolean;

    /**
     * Get and parse JSON value from path
     * @param path Data path
     * @param token Optional JWT token for auth
     * @returns parsed value or null
     * @throws Error if access denied
     */
    get(path: string, token?: string | null): any;

    /**
     * Setup default Firebase-style rules
     * @returns success
     */
    setupDefaultRules(): boolean;
}