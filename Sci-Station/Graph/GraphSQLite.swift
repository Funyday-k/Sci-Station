import Foundation
import SQLite3

nonisolated struct GraphSQLiteFailure: Error, CustomStringConvertible, Sendable {
    let code: Int32
    let message: String
    let sql: String?

    var description: String {
        if let sql { return "SQLite \(code): \(message) [\(sql)]" }
        return "SQLite \(code): \(message)"
    }

    var isCorruption: Bool {
        let primaryCode = code & 0xff
        return primaryCode == SQLITE_CORRUPT || primaryCode == SQLITE_NOTADB
    }
}

private nonisolated let graphSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Small SQLite wrapper owned exclusively by `GraphRepository`'s actor.
/// Keeping SQL mechanics here makes transaction and migration behavior easy to
/// audit without exposing a second persistence API.
final class GraphSQLiteDatabase {
    let url: URL
    private(set) var handle: OpaquePointer?

    init(url: URL, readOnly: Bool = false) throws {
        self.url = url
        var opened: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &opened, flags, nil)
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            if let opened { sqlite3_close_v2(opened) }
            throw GraphSQLiteFailure(code: result, message: message, sql: nil)
        }
        handle = opened
        sqlite3_extended_result_codes(opened, 1)
        sqlite3_busy_timeout(opened, 5_000)
    }

    deinit {
        close()
    }

    func close() {
        guard let handle else { return }
        sqlite3_close_v2(handle)
        self.handle = nil
    }

    func execute(_ sql: String) throws {
        guard let handle else { throw GraphSQLiteFailure(code: SQLITE_MISUSE, message: "database closed", sql: sql) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorMessage)
            throw GraphSQLiteFailure(code: result, message: message, sql: sql)
        }
    }

    func prepare(_ sql: String) throws -> GraphSQLiteStatement {
        guard let handle else { throw GraphSQLiteFailure(code: SQLITE_MISUSE, message: "database closed", sql: sql) }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw GraphSQLiteFailure(code: result, message: String(cString: sqlite3_errmsg(handle)), sql: sql)
        }
        return GraphSQLiteStatement(database: self, handle: statement, sql: sql)
    }

    func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        return try statement.stepRow() ? statement.int(at: 0) : 0
    }

    func scalarString(_ sql: String) throws -> String? {
        let statement = try prepare(sql)
        return try statement.stepRow() ? statement.string(at: 0) : nil
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func backup(to destinationURL: URL) throws {
        let destination = try GraphSQLiteDatabase(url: destinationURL)
        guard let sourceHandle = handle, let destinationHandle = destination.handle else {
            throw GraphSQLiteFailure(code: SQLITE_MISUSE, message: "database closed during backup", sql: nil)
        }
        guard let backup = sqlite3_backup_init(destinationHandle, "main", sourceHandle, "main") else {
            throw GraphSQLiteFailure(
                code: sqlite3_errcode(destinationHandle),
                message: String(cString: sqlite3_errmsg(destinationHandle)),
                sql: "sqlite3_backup_init"
            )
        }
        var stepResult: Int32 = SQLITE_OK
        repeat {
            stepResult = sqlite3_backup_step(backup, 256)
            if stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED {
                sqlite3_sleep(10)
            }
        } while stepResult == SQLITE_OK || stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw GraphSQLiteFailure(
                code: stepResult == SQLITE_DONE ? finishResult : stepResult,
                message: String(cString: sqlite3_errmsg(destinationHandle)),
                sql: "sqlite3_backup_step"
            )
        }
        // A backup must be a self-contained file. Copying a WAL-mode header
        // without its sidecars makes a later read-only integrity check fail.
        try destination.execute("PRAGMA journal_mode = DELETE")
        try destination.execute("PRAGMA synchronous = FULL")
        destination.close()
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: destinationURL.path + suffix)
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    fileprivate func failure(code: Int32, sql: String) -> GraphSQLiteFailure {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database closed"
        return GraphSQLiteFailure(code: code, message: message, sql: sql)
    }
}

final class GraphSQLiteStatement {
    private unowned let database: GraphSQLiteDatabase
    private var handle: OpaquePointer?
    private let sql: String

    fileprivate init(database: GraphSQLiteDatabase, handle: OpaquePointer, sql: String) {
        self.database = database
        self.handle = handle
        self.sql = sql
    }

    deinit {
        if let handle { sqlite3_finalize(handle) }
    }

    func reset() throws {
        guard let handle else { throw database.failure(code: SQLITE_MISUSE, sql: sql) }
        let resetResult = sqlite3_reset(handle)
        guard resetResult == SQLITE_OK else { throw database.failure(code: resetResult, sql: sql) }
        let clearResult = sqlite3_clear_bindings(handle)
        guard clearResult == SQLITE_OK else { throw database.failure(code: clearResult, sql: sql) }
    }

    func bind(_ value: String?, at index: Int32) throws {
        guard let handle else { throw database.failure(code: SQLITE_MISUSE, sql: sql) }
        let result: Int32
        if let value {
            result = sqlite3_bind_text(handle, index, value, -1, graphSQLiteTransient)
        } else {
            result = sqlite3_bind_null(handle, index)
        }
        guard result == SQLITE_OK else { throw database.failure(code: result, sql: sql) }
    }

    func bind(_ value: Data, at index: Int32) throws {
        guard let handle else { throw database.failure(code: SQLITE_MISUSE, sql: sql) }
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(handle, index, bytes.baseAddress, Int32(bytes.count), graphSQLiteTransient)
        }
        guard result == SQLITE_OK else { throw database.failure(code: result, sql: sql) }
    }

    func bind(_ value: Double, at index: Int32) throws {
        guard let handle else { throw database.failure(code: SQLITE_MISUSE, sql: sql) }
        let result = sqlite3_bind_double(handle, index, value)
        guard result == SQLITE_OK else { throw database.failure(code: result, sql: sql) }
    }

    func bind(_ value: Int, at index: Int32) throws {
        guard let handle else { throw database.failure(code: SQLITE_MISUSE, sql: sql) }
        let result = sqlite3_bind_int64(handle, index, sqlite3_int64(value))
        guard result == SQLITE_OK else { throw database.failure(code: result, sql: sql) }
    }

    func bind(_ value: Int?, at index: Int32) throws {
        guard let value else {
            guard let handle else { throw database.failure(code: SQLITE_MISUSE, sql: sql) }
            let result = sqlite3_bind_null(handle, index)
            guard result == SQLITE_OK else { throw database.failure(code: result, sql: sql) }
            return
        }
        try bind(value, at: index)
    }

    func stepDone() throws {
        guard let handle else { throw database.failure(code: SQLITE_MISUSE, sql: sql) }
        let result = sqlite3_step(handle)
        guard result == SQLITE_DONE else { throw database.failure(code: result, sql: sql) }
    }

    func stepRow() throws -> Bool {
        guard let handle else { throw database.failure(code: SQLITE_MISUSE, sql: sql) }
        let result = sqlite3_step(handle)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw database.failure(code: result, sql: sql)
    }

    func string(at index: Int32) -> String? {
        guard let handle, sqlite3_column_type(handle, index) != SQLITE_NULL,
              let value = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: value)
    }

    func data(at index: Int32) -> Data {
        guard let handle, let bytes = sqlite3_column_blob(handle, index) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, index)))
    }

    func double(at index: Int32) -> Double {
        guard let handle else { return 0 }
        return sqlite3_column_double(handle, index)
    }

    func int(at index: Int32) -> Int {
        guard let handle else { return 0 }
        return Int(sqlite3_column_int64(handle, index))
    }
}
