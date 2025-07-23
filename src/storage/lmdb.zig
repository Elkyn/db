const std = @import("std");
const c = @cImport({
    @cInclude("lmdb.h");
});

const log = std.log.scoped(.lmdb);

pub const LmdbError = error{
    InitFailed,
    TransactionFailed,
    PutFailed,
    GetFailed,
    DeleteFailed,
    NotFound,
    PermissionDenied,
    DiskFull,
    Corrupted,
    CursorFailed,
};

/// Convert LMDB error codes to Zig errors
fn lmdbToZigError(rc: c_int) LmdbError {
    return switch (rc) {
        c.MDB_NOTFOUND => error.NotFound,
        c.MDB_MAP_FULL => error.DiskFull,
        c.MDB_CORRUPTED => error.Corrupted,
        // MDB_PERM might not be available in all LMDB versions
        // Use numeric value -30783 if needed
        else => error.InitFailed,
    };
}

/// LMDB environment wrapper
pub const Environment = struct {
    env: ?*c.MDB_env,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Environment {
        var env: ?*c.MDB_env = null;
        
        // Create environment
        var rc = c.mdb_env_create(&env);
        if (rc != 0) {
            log.err("Failed to create LMDB environment: {d}", .{rc});
            return error.InitFailed;
        }
        errdefer _ = c.mdb_env_close(env);

        // Set max databases (we'll use named databases for different trees)
        rc = c.mdb_env_set_maxdbs(env, 10);
        if (rc != 0) return error.InitFailed;

        // Set map size (1GB for now, can be increased)
        const map_size: usize = 1024 * 1024 * 1024;
        rc = c.mdb_env_set_mapsize(env, map_size);
        if (rc != 0) return error.InitFailed;

        // Open environment
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        
        // Create directory if it doesn't exist
        std.fs.makeDirAbsolute(path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        
        rc = c.mdb_env_open(env, path_z, c.MDB_WRITEMAP | c.MDB_NOMETASYNC, 0o664);
        if (rc != 0) {
            log.err("Failed to open LMDB environment at {s}: {d}", .{path, rc});
            return lmdbToZigError(rc);
        }

        return Environment{
            .env = env,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Environment) void {
        if (self.env) |env| {
            c.mdb_env_close(env);
            self.env = null;
        }
    }

    pub fn beginTxn(self: *Environment, readonly: bool) !Transaction {
        return Transaction.init(self, readonly);
    }
};

/// LMDB transaction wrapper
pub const Transaction = struct {
    txn: ?*c.MDB_txn,
    env: *Environment,
    committed: bool,

    pub fn init(env: *Environment, readonly: bool) !Transaction {
        var txn: ?*c.MDB_txn = null;
        const flags: c_uint = if (readonly) c.MDB_RDONLY else 0;
        
        const rc = c.mdb_txn_begin(env.env, null, flags, &txn);
        if (rc != 0) return error.TransactionFailed;

        return Transaction{
            .txn = txn,
            .env = env,
            .committed = false,
        };
    }

    pub fn deinit(self: *Transaction) void {
        if (self.txn != null and !self.committed) {
            c.mdb_txn_abort(self.txn);
            self.txn = null;
        }
    }

    pub fn commit(self: *Transaction) !void {
        if (self.committed) return;
        
        const rc = c.mdb_txn_commit(self.txn);
        if (rc != 0) return error.TransactionFailed;
        
        self.committed = true;
        self.txn = null;
    }

    pub fn openDatabase(self: *Transaction, name: ?[]const u8) !Database {
        return Database.init(self, name);
    }
};

/// Cursor entry type
pub const CursorEntry = struct {
    key: []const u8,
    value: []const u8,
};

/// LMDB cursor wrapper
pub const Cursor = struct {
    cursor: ?*c.MDB_cursor,
    db: *Database,

    pub fn init(db: *Database) !Cursor {
        var cursor: ?*c.MDB_cursor = null;
        const rc = c.mdb_cursor_open(db.txn.txn, db.dbi, &cursor);
        if (rc != 0) return error.InitFailed;
        
        return Cursor{
            .cursor = cursor,
            .db = db,
        };
    }

    pub fn deinit(self: *Cursor) void {
        if (self.cursor) |cursor| {
            c.mdb_cursor_close(cursor);
            self.cursor = null;
        }
    }

    pub fn seek(self: *Cursor, key: []const u8) !?CursorEntry {
        var key_val = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };
        var data_val: c.MDB_val = undefined;

        const rc = c.mdb_cursor_get(self.cursor, &key_val, &data_val, c.MDB_SET_RANGE);
        if (rc == c.MDB_NOTFOUND) return null;
        if (rc != 0) return error.CursorFailed;

        const result_key: [*]const u8 = @ptrCast(key_val.mv_data);
        const result_data: [*]const u8 = @ptrCast(data_val.mv_data);
        
        return CursorEntry{
            .key = result_key[0..key_val.mv_size],
            .value = result_data[0..data_val.mv_size],
        };
    }
    
    pub fn goToKey(self: *Cursor, key: []const u8) !?CursorEntry {
        var key_val = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };
        var data_val: c.MDB_val = undefined;

        const rc = c.mdb_cursor_get(self.cursor, &key_val, &data_val, c.MDB_SET);
        if (rc == c.MDB_NOTFOUND) return null;
        if (rc != 0) return error.CursorFailed;

        const result_key: [*]const u8 = @ptrCast(key_val.mv_data);
        const result_data: [*]const u8 = @ptrCast(data_val.mv_data);
        
        return CursorEntry{
            .key = result_key[0..key_val.mv_size],
            .value = result_data[0..data_val.mv_size],
        };
    }

    pub fn next(self: *Cursor) !?CursorEntry {
        var key_val: c.MDB_val = undefined;
        var data_val: c.MDB_val = undefined;

        const rc = c.mdb_cursor_get(self.cursor, &key_val, &data_val, c.MDB_NEXT);
        if (rc == c.MDB_NOTFOUND) return null;
        if (rc != 0) return error.CursorFailed;

        const result_key: [*]const u8 = @ptrCast(key_val.mv_data);
        const result_data: [*]const u8 = @ptrCast(data_val.mv_data);
        
        return CursorEntry{
            .key = result_key[0..key_val.mv_size],
            .value = result_data[0..data_val.mv_size],
        };
    }
};

/// LMDB database wrapper
pub const Database = struct {
    dbi: c.MDB_dbi,
    txn: *Transaction,

    pub fn init(txn: *Transaction, name: ?[]const u8) !Database {
        var dbi: c.MDB_dbi = undefined;
        
        var name_z: ?[*:0]const u8 = null;
        if (name) |n| {
            name_z = try txn.env.allocator.dupeZ(u8, n);
        }
        defer if (name_z) |n| txn.env.allocator.free(std.mem.span(n));
        
        const rc = c.mdb_dbi_open(txn.txn, name_z, c.MDB_CREATE, &dbi);
        if (rc != 0) return error.InitFailed;

        return Database{
            .dbi = dbi,
            .txn = txn,
        };
    }

    pub fn openCursor(self: *Database) !Cursor {
        return try Cursor.init(self);
    }

    pub fn put(self: *Database, key: []const u8, value: []const u8) !void {
        var key_val = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };
        
        var data_val = c.MDB_val{
            .mv_size = value.len,
            .mv_data = @constCast(@ptrCast(value.ptr)),
        };

        const rc = c.mdb_put(self.txn.txn, self.dbi, &key_val, &data_val, 0);
        if (rc != 0) return error.PutFailed;
    }

    pub fn get(self: *Database, key: []const u8) ![]const u8 {
        var key_val = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };
        
        var data_val: c.MDB_val = undefined;

        const rc = c.mdb_get(self.txn.txn, self.dbi, &key_val, &data_val);
        if (rc == c.MDB_NOTFOUND) return error.NotFound;
        if (rc != 0) return error.GetFailed;

        const data_ptr: [*]const u8 = @ptrCast(data_val.mv_data);
        return data_ptr[0..data_val.mv_size];
    }

    pub fn delete(self: *Database, key: []const u8) !void {
        var key_val = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };

        const rc = c.mdb_del(self.txn.txn, self.dbi, &key_val, null);
        if (rc == c.MDB_NOTFOUND) return error.NotFound;
        if (rc != 0) return error.DeleteFailed;
    }
};