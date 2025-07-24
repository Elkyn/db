// Master test file that imports all test files
// This allows tests to use relative imports properly since they're compiled from src/ context

const std = @import("std");

// Storage tests
pub const tree_test = @import("storage/tree_test.zig");
pub const lmdb_test = @import("storage/lmdb_test.zig");
pub const lmdb_cursor_test = @import("storage/lmdb_cursor_test.zig");
pub const storage_test = @import("storage/storage_test.zig");
pub const event_emitter_test = @import("storage/event_emitter_test.zig");
pub const simple_events_test = @import("storage/simple_events_test.zig");
pub const storage_update_test = @import("storage/storage_update_test.zig");
pub const storage_cursor_test = @import("storage/storage_cursor_test.zig");
pub const storage_events_test = @import("storage/storage_events_test.zig");
pub const value_test = @import("storage/value_test.zig");
pub const msgpack_test = @import("storage/msgpack_test.zig");
pub const storage_msgpack_test = @import("storage/storage_msgpack_test.zig");

// Auth tests
pub const jwt_test = @import("auth/jwt_test.zig");
pub const context_test = @import("auth/context_test.zig");

// Rules tests
pub const parser_test = @import("rules/parser_test.zig");
pub const evaluator_test = @import("rules/evaluator_test.zig");
pub const rule_test = @import("rules/rule_test.zig");
pub const engine_test = @import("rules/engine_test.zig");

// API tests
pub const simple_http_server_auth_test = @import("api/simple_http_server_auth_test.zig");
pub const thread_pool_test = @import("api/thread_pool_test.zig");

// Realtime tests
pub const sse_manager_test = @import("realtime/sse_manager_test.zig");

// Integration tests are run separately via scripts/run_integration_tests.sh

test {
    // Reference all test modules to ensure they run
    _ = tree_test;
    _ = lmdb_test;
    _ = lmdb_cursor_test;
    _ = storage_test;
    _ = event_emitter_test;
    _ = simple_events_test;
    _ = storage_update_test;
    _ = storage_cursor_test;
    _ = storage_events_test;
    _ = value_test;
    _ = msgpack_test;
    _ = storage_msgpack_test;
    _ = jwt_test;
    _ = context_test;
    _ = parser_test;
    _ = evaluator_test;
    _ = rule_test;
    _ = engine_test;
    _ = simple_http_server_auth_test;
    _ = thread_pool_test;
    _ = sse_manager_test;
}