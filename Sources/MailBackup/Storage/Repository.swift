import Foundation
import GRDB

/// Database operations for accounts, folders, and messages.
struct Repository {
    let database: Database
    private var writer: any DatabaseWriter { database.writer }

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

    func deleteFolder(id: Int64) throws {
        _ = try writer.write { try Folder.deleteOne($0, key: id) }
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

    @discardableResult
    func insertMessage(_ message: Message) throws -> Message {
        try writer.write { db in
            var stored = message
            try stored.insert(db)
            return stored
        }
    }

    func messageIds(folderId: Int64) throws -> [Int64] {
        try writer.read { db in
            try Int64.fetchAll(db, sql: "SELECT id FROM message WHERE folderId = ?", arguments: [folderId])
        }
    }

    /// UIDs of messages whose body hasn't been downloaded yet (e.g. an
    /// interrupted headers-first run), so the next sync can complete them.
    func bodylessUIDs(folderId: Int64) throws -> [Int] {
        try writer.read { db in
            try Int.fetchAll(db, sql: "SELECT uid FROM message WHERE folderId = ? AND hasBody = 0", arguments: [folderId])
        }
    }

    func updateMessageBody(folderId: Int64, uid: Int, bodyText: String?, snippet: String?, hasAttachments: Bool, size: Int?) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                UPDATE message
                SET bodyText = ?, snippet = ?, hasAttachments = ?, size = COALESCE(?, size), hasBody = 1
                WHERE folderId = ? AND uid = ?
                """,
                arguments: [bodyText, snippet, hasAttachments, size, folderId, uid]
            )
        }
    }

    func deleteMessages(folderId: Int64) throws {
        _ = try writer.write { db in
            try Message.filter(Column("folderId") == folderId).deleteAll(db)
        }
    }

    func deleteMessages(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        _ = try writer.write { db in try Message.deleteAll(db, keys: ids) }
    }

    func message(id: Int64) throws -> Message? {
        try writer.read { try Message.fetchOne($0, key: id) }
    }

    /// A page of messages in a folder. Excludes the large `bodyText` column.
    func messages(folderId: Int64, filter: MessageFilter = MessageFilter(), limit: Int = 2000, offset: Int = 0) throws -> [Message] {
        try writer.read { db in
            var request = Message.select(Message.listColumns).filter(Column("folderId") == folderId)
            if filter.unreadOnly {
                request = request.filter(sql: "(flags IS NULL OR flags NOT LIKE '%Seen%')")
            }
            if filter.hasAttachmentOnly {
                request = request.filter(Column("hasAttachments") == true)
            }
            let order = filter.sort == .oldest
                ? "COALESCE(internalDate, date, createdAt) ASC"
                : "COALESCE(internalDate, date, createdAt) DESC"
            return try request.order(sql: order).limit(limit, offset: offset).fetchAll(db)
        }
    }

    /// Per-folder message counts for an account in a single grouped query.
    func folderMessageCounts(accountId: String) throws -> [Int64: Int] {
        try writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT folderId, COUNT(*) AS c FROM message WHERE accountId = ? GROUP BY folderId",
                arguments: [accountId]
            )
            var result: [Int64: Int] = [:]
            for row in rows { result[row["folderId"]] = row["c"] }
            return result
        }
    }

    /// A page of full-text search results, optionally scoped to a folder or
    /// account. Ordered by FTS rank.
    func searchMessages(query: String, folderId: Int64? = nil, accountId: String? = nil, filter: MessageFilter = MessageFilter(), limit: Int = 100, offset: Int = 0) throws -> [Message] {
        let expression = Repository.ftsExpression(query)
        guard !expression.isEmpty else { return [] }

        var sql = """
        SELECT \(Repository.messageListSelection) FROM message
        JOIN message_fts ON message_fts.rowid = message.id
        WHERE message_fts MATCH ?
        """
        var arguments: [DatabaseValueConvertible] = [expression]
        appendScope(folderId: folderId, accountId: accountId, to: &sql, arguments: &arguments)
        appendFilter(filter, to: &sql)
        switch filter.sort {
        case .oldest: sql += " ORDER BY COALESCE(message.internalDate, message.date, message.createdAt) ASC"
        case .newest: sql += " ORDER BY COALESCE(message.internalDate, message.date, message.createdAt) DESC"
        case .relevance: sql += " ORDER BY rank"
        }
        sql += " LIMIT ? OFFSET ?"
        arguments.append(limit)
        arguments.append(offset)

        return try writer.read { db in
            try Message.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    /// Total number of full-text matches for a query (for "N results").
    func searchMessageCount(query: String, folderId: Int64? = nil, accountId: String? = nil, filter: MessageFilter = MessageFilter()) throws -> Int {
        let expression = Repository.ftsExpression(query)
        guard !expression.isEmpty else { return 0 }

        var sql = """
        SELECT COUNT(*) FROM message
        JOIN message_fts ON message_fts.rowid = message.id
        WHERE message_fts MATCH ?
        """
        var arguments: [DatabaseValueConvertible] = [expression]
        appendScope(folderId: folderId, accountId: accountId, to: &sql, arguments: &arguments)
        appendFilter(filter, to: &sql)

        return try writer.read { db in
            try Int.fetchOne(db, sql: sql, arguments: StatementArguments(arguments)) ?? 0
        }
    }

    private func appendFilter(_ filter: MessageFilter, to sql: inout String) {
        if filter.unreadOnly {
            sql += " AND (message.flags IS NULL OR message.flags NOT LIKE '%Seen%')"
        }
        if filter.hasAttachmentOnly {
            sql += " AND message.hasAttachments = 1"
        }
    }

    /// `message.col, message.col, …` for the list columns (excludes bodyText).
    private static let messageListSelection = Message.listColumnNames
        .map { "message.\($0)" }
        .joined(separator: ", ")

    private func appendScope(folderId: Int64?, accountId: String?, to sql: inout String, arguments: inout [DatabaseValueConvertible]) {
        if let folderId {
            sql += " AND message.folderId = ?"
            arguments.append(folderId)
        } else if let accountId {
            sql += " AND message.accountId = ?"
            arguments.append(accountId)
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
