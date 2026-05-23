import Foundation
import GRDB

/// Database operations for accounts, folders, and messages.
struct Repository {
    let database: Database
    private var writer: DatabaseQueue { database.writer }

    // MARK: - Accounts

    func allAccounts() throws -> [Account] {
        try writer.read { try Account.order(Column("createdAt")).fetchAll($0) }
    }

    func account(id: String) throws -> Account? {
        try writer.read { try Account.fetchOne($0, key: id) }
    }

    func saveAccount(_ account: Account) throws {
        try writer.write { try account.save($0) }
    }

    func deleteAccount(id: String) throws {
        _ = try writer.write { try Account.deleteOne($0, key: id) }
    }

    // MARK: - Folders

    func folders(accountId: String) throws -> [Folder] {
        try writer.read {
            try Folder.filter(Column("accountId") == accountId).order(Column("name")).fetchAll($0)
        }
    }

    func folder(accountId: String, name: String) throws -> Folder? {
        try writer.read {
            try Folder.filter(Column("accountId") == accountId && Column("name") == name).fetchOne($0)
        }
    }

    @discardableResult
    func upsertFolder(_ folder: Folder) throws -> Folder {
        try writer.write { db in
            var resolved = folder
            if let existing = try Folder
                .filter(Column("accountId") == folder.accountId && Column("name") == folder.name)
                .fetchOne(db) {
                resolved.id = existing.id
                try resolved.update(db)
            } else {
                try resolved.insert(db)
            }
            return resolved
        }
    }

    func updateFolderState(id: Int64, uidValidity: Int?, uidNext: Int?, lastSyncedAt: Date) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE folder SET uidValidity = ?, uidNext = ?, lastSyncedAt = ? WHERE id = ?",
                arguments: [uidValidity, uidNext, lastSyncedAt, id]
            )
        }
    }

    // MARK: - Messages

    func existingUIDs(folderId: Int64) throws -> Set<Int> {
        try writer.read { db in
            let uids = try Int.fetchAll(db, sql: "SELECT uid FROM message WHERE folderId = ?", arguments: [folderId])
            return Set(uids)
        }
    }

    func insertMessage(_ message: Message) throws {
        try writer.write { db in
            var stored = message
            try stored.insert(db)
        }
    }

    func deleteMessages(folderId: Int64) throws {
        _ = try writer.write { db in
            try Message.filter(Column("folderId") == folderId).deleteAll(db)
        }
    }

    func message(id: Int64) throws -> Message? {
        try writer.read { try Message.fetchOne($0, key: id) }
    }

    /// Messages in a folder, newest first.
    func messages(folderId: Int64, limit: Int = 2000) throws -> [Message] {
        try writer.read { db in
            try Message
                .filter(Column("folderId") == folderId)
                .order(sql: "COALESCE(internalDate, date, createdAt) DESC")
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Full-text search, optionally scoped to a folder or account. Newest first
    /// within relevance is approximated by FTS rank.
    func searchMessages(query: String, folderId: Int64? = nil, accountId: String? = nil, limit: Int = 500) throws -> [Message] {
        let expression = Repository.ftsExpression(query)
        guard !expression.isEmpty else { return [] }

        var sql = """
        SELECT message.* FROM message
        JOIN message_fts ON message_fts.rowid = message.id
        WHERE message_fts MATCH ?
        """
        var arguments: [DatabaseValueConvertible] = [expression]
        if let folderId {
            sql += " AND message.folderId = ?"
            arguments.append(folderId)
        } else if let accountId {
            sql += " AND message.accountId = ?"
            arguments.append(accountId)
        }
        sql += " ORDER BY rank LIMIT ?"
        arguments.append(limit)

        return try writer.read { db in
            try Message.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    /// Builds a safe FTS5 MATCH expression: each whitespace-separated term
    /// becomes a quoted prefix query joined by implicit AND.
    static func ftsExpression(_ input: String) -> String {
        let terms = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let quoted = terms.compactMap { term -> String? in
            let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
            return escaped.isEmpty ? nil : "\"\(escaped)\"*"
        }
        return quoted.joined(separator: " ")
    }

    func messageCount(accountId: String) throws -> Int {
        try writer.read { try Message.filter(Column("accountId") == accountId).fetchCount($0) }
    }

    func messageCount(folderId: Int64) throws -> Int {
        try writer.read { try Message.filter(Column("folderId") == folderId).fetchCount($0) }
    }

    func totalArchivedSize(accountId: String) throws -> Int {
        try writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(size), 0) FROM message WHERE accountId = ?",
                arguments: [accountId]
            ) ?? 0
        }
    }
}
