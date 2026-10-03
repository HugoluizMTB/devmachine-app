import Foundation
import SQLite3

/// A read-only look into a database another program owns and may be writing
/// at that moment. It opens with `mode=ro`, never `immutable=1`, so rows
/// still in the write-ahead log are seen; it never writes, and a locked or
/// missing database reads as no rows rather than an error.
final class ContextSQLite {
    private var db: OpaquePointer?

    init?(path: URL) {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        var components = URLComponents()
        components.scheme = "file"
        components.path = path.path
        components.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        guard let uri = components.string else { return nil }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 200)
    }

    deinit {
        sqlite3_close(db)
    }

    /// Each row as column name → `String`, `Int64`, `Double` or nil. Text
    /// is bound by position; a failed statement returns no rows.
    func rows(_ sql: String, _ arguments: [String] = []) -> [[String: Any?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, argument) in arguments.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), argument, -1, transient)
        }
        var rows: [[String: Any?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any?] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, column)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, column)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, column))
                default: row[name] = .some(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }
}

extension Dictionary where Key == String, Value == Any? {
    func text(_ key: String) -> String? { self[key] as? String }

    func number(_ key: String) -> Double? {
        switch self[key] {
        case let value as Int64: return Double(value)
        case let value as Double: return value
        case let value as String: return Double(value)
        default: return nil
        }
    }
}
