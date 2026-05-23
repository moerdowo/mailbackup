import Foundation
import GRDB

/// Owns the SQLite connection and schema migrations for the local archive.
final class Database {
    /// A WAL-backed pool so reads (browsing the archive) run concurrently with
    /// the sync engine's writes. In-memory test databases use a queue.
    let writer: any DatabaseWriter

    init(url: URL) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        try Self.migrator.migrate(pool)
        writer = pool
    }

    /// In-memory database, used by tests and self-checks.
    init() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        try Self.migrator.migrate(queue)
        writer = queue
    }

    static func makeDefault() throws -> Database {
        try Database(url: try AppPaths.defaultDatabaseURL())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "account") { t in
                t.primaryKey("id", .text)
                t.column("displayName", .text).notNull()
                t.column("email", .text).notNull()
                t.column("imapHost", .text).notNull()
                t.column("imapPort", .integer).notNull()
                t.column("security", .text).notNull()
                t.column("username", .text).notNull()
                t.column("downloadAttachments", .boolean).notNull().defaults(to: true)
                t.column("syncIntervalMinutes", .integer)
                t.column("archivePath", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "folder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .text).notNull()
                    .references("account", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("uidValidity", .integer)
                t.column("uidNext", .integer)
                t.column("lastSyncedAt", .datetime)
                t.uniqueKey(["accountId", "name"])
            }

            try db.create(table: "message") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .text).notNull()
                    .references("account", onDelete: .cascade)
                t.column("folderId", .integer).notNull()
                    .references("folder", onDelete: .cascade)
                t.column("uid", .integer).notNull()
                t.column("messageId", .text)
                t.column("subject", .text)
                t.column("fromName", .text)
                t.column("fromAddress", .text)
                t.column("toAddresses", .text)
                t.column("ccAddresses", .text)
                t.column("date", .datetime)
                t.column("internalDate", .datetime)
                t.column("size", .integer)
                t.column("flags", .text)
                t.column("hasAttachments", .boolean).notNull().defaults(to: false)
                t.column("emlPath", .text).notNull()
                t.column("bodyText", .text)
                t.column("snippet", .text)
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["folderId", "uid"])
            }
            try db.create(indexOn: "message", columns: ["accountId"])
            try db.create(indexOn: "message", columns: ["folderId"])

            // Full-text search over message content. Uses FTS5 external-content
            // mode synchronized with the `message` table: GRDB installs triggers
            // that keep `message_fts` in step on insert/update/delete.
            try db.create(virtualTable: "message_fts", using: FTS5()) { t in
                t.synchronize(withTable: "message")
                t.column("subject")
                t.column("fromName")
                t.column("fromAddress")
                t.column("toAddresses")
                t.column("ccAddresses")
                t.column("bodyText")
                t.tokenizer = .porter(wrapping: .unicode61())
            }
        }

        migrator.registerMigration("v2-account-paused") { db in
            try db.alter(table: "account") { t in
                t.add(column: "isPaused", .boolean).notNull().defaults(to: false)
            }
        }

        // Expression index matching the message-list ORDER BY, so paged folder
        // reads use an indexed scan instead of sorting the whole folder.
        migrator.registerMigration("v3-message-date-index") { db in
            try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS message_folder_date
            ON message(folderId, COALESCE(internalDate, date, createdAt) DESC)
            """)
        }

        return migrator
    }
}
