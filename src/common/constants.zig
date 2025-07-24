// Constants for Elkyn DB - centralized configuration values

const std = @import("std");

// HTTP Status Codes
pub const HTTP_OK = 200;
pub const HTTP_FOUND = 302;
pub const HTTP_BAD_REQUEST = 400;
pub const HTTP_UNAUTHORIZED = 401;
pub const HTTP_FORBIDDEN = 403;
pub const HTTP_NOT_FOUND = 404;
pub const HTTP_METHOD_NOT_ALLOWED = 405;
pub const HTTP_INTERNAL_SERVER_ERROR = 500;

// Buffer Sizes
pub const HTTP_REQUEST_BUFFER_SIZE = 4096;
pub const HTTP_HEADER_BUFFER_SIZE = 512;
pub const SSE_EVENT_BUFFER_SIZE = 1024;
pub const PATH_BUFFER_SIZE = 256;
pub const MAX_PATH_LENGTH = 1024;
pub const MAX_RULES_FILE_SIZE = 1024 * 1024; // 1MB

// Time Constants
pub const HEARTBEAT_INTERVAL_NS = 30 * std.time.ns_per_s; // 30 seconds
pub const JWT_DEFAULT_EXPIRY_SECONDS = 3600; // 1 hour
pub const TEST_SLEEP_MS = 100 * std.time.ns_per_ms; // 100ms for tests
pub const BOOT_TIME_TARGET_MS = 500.0; // Sub-500ms boot target

// Server Defaults
pub const DEFAULT_SERVER_PORT: u16 = 8080;
pub const DEFAULT_DATA_DIR = "./data";
pub const SERVER_ADDRESS = "127.0.0.1";

// Database Configuration
pub const LMDB_MAX_DBS = 10;
pub const LMDB_MAP_SIZE = 1024 * 1024 * 1024; // 1GB

// Test Data
pub const TEST_USER_COUNT = 1000;
pub const TEST_SIBLING_COUNT = 10;

// Numeric Precision
pub const FLOAT_COMPARISON_EPSILON = 0.001;