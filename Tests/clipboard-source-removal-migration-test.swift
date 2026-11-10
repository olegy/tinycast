import Foundation
import SQLite3

@main
@MainActor
struct ClipboardSourceRemovalMigrationTest {
    static var failures = 0

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-source-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clipboard.sqlite3")

        ClipboardSourceRemovalMigration.run(database: url)
        check("a missing history stays missing", !FileManager.default.fileExists(atPath: url.path))

        try legacyDatabase(at: url)
        check("the legacy table has the column", columnExists(in: url))
        ClipboardSourceRemovalMigration.run(database: url)
        check("the column is dropped", !columnExists(in: url))
        ClipboardSourceRemovalMigration.run(database: url)
        check("a second run changes nothing", !columnExists(in: url))

        let store = ClipboardStore(directory: directory)
        store.load()
        check("the clip survives", store.items.map(\.text) == ["kept clip"])
        check("its pin survives", store.items.first?.isPinned == true)
        check("search still finds it", store.search("kept", filter: .all).count == 1)
        store.addText("new clip")
        check("a new clip inserts", store.items.first?.text == "new clip")
        store.close()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    /// The table, index and FTS triggers as a release that still recorded the source app left them.
    private static func legacyDatabase(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(db) }
        let sql = """
            CREATE TABLE items(
              id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, text TEXT, image_path TEXT,
              created_at REAL NOT NULL, source_app TEXT, pinned_at REAL
            );
            CREATE INDEX items_created_at ON items(created_at);
            CREATE INDEX items_pinned_at ON items(pinned_at) WHERE pinned_at IS NOT NULL;
            CREATE VIRTUAL TABLE items_fts USING fts5(
              text, content='items', content_rowid='rowid', tokenize='trigram'
            );
            CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
              INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
            END;
            CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
              INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
            END;
            CREATE TRIGGER items_au AFTER UPDATE OF rowid, text ON items BEGIN
              INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
              INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
            END;
            INSERT INTO items VALUES(
              '\(UUID().uuidString)', 'text', 'kept clip', NULL, \(Date().timeIntervalSince1970),
              'com.apple.Safari', \(Date().timeIntervalSince1970)
            );
            """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func columnExists(in url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_close(db) }
        return ClipboardSourceRemovalMigration.hasSourceColumn(db)
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}
