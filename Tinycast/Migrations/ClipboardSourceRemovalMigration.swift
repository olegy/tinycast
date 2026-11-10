import Foundation
import SQLite3

/// Drops `items.source_app`, so a history no longer records which app each clip came from.
enum ClipboardSourceRemovalMigration {
    static func run(database url: URL) {
        var db: OpaquePointer?
        // No `CREATE`: a missing history has nothing to repair and must stay missing.
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return
        }
        defer { sqlite3_close_v2(db) }
        sqlite3_busy_timeout(db, 1000)
        guard hasSourceColumn(db) else { return }
        sqlite3_exec(db, "ALTER TABLE items DROP COLUMN source_app", nil, nil, nil)
    }

    static func hasSourceColumn(_ db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM pragma_table_info('items') WHERE name = 'source_app'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
