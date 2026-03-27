import Foundation
import SQLite3

/// Minimal SQLite wrapper. No ORM, no dependencies.
public final class SQLiteDatabase: @unchecked Sendable {
    private let db: OpaquePointer

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError.openFailed(msg)
        }
        self.db = handle

        // Enable WAL mode for better concurrent read/write
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
    }

    /// Run a statement that doesn't return rows.
    public func run(_ sql: String, params: [SQLiteValue] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bind(stmt: stmt!, params: params)

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE else {
            throw SQLiteError.runFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Query rows.
    public func query(_ sql: String, params: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bind(stmt: stmt!, params: params)

        var rows: [[String: SQLiteValue]] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)
                switch type {
                case SQLITE_INTEGER:
                    row[name] = .int(Int(sqlite3_column_int64(stmt, i)))
                case SQLITE_FLOAT:
                    row[name] = .double(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT:
                    row[name] = .text(String(cString: sqlite3_column_text(stmt, i)))
                case SQLITE_NULL:
                    row[name] = .null
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: - Binding

    private func bind(stmt: OpaquePointer, params: [SQLiteValue]) throws {
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case .text(let s):
                sqlite3_bind_text(stmt, idx, (s as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .int(let n):
                sqlite3_bind_int64(stmt, idx, Int64(n))
            case .double(let d):
                sqlite3_bind_double(stmt, idx, d)
            case .null:
                sqlite3_bind_null(stmt, idx)
            }
        }
    }
}

// MARK: - SQLiteValue

public enum SQLiteValue: Sendable {
    case text(String)
    case int(Int)
    case double(Double)
    case null

    public var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .int(let n) = self { return n }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let d) = self { return d }
        return nil
    }
}

// MARK: - SQLiteError

public enum SQLiteError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case runFailed(String)
}
