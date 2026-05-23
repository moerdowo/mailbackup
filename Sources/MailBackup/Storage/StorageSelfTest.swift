import Foundation
import GRDB

/// Development smoke test for the storage layer, run via
/// `MAILBACKUP_STORAGE_TEST=1 ./MailBackup`. Exercises migrations, the
/// `.eml` store, FTS5 sync triggers, and the Keychain roundtrip, then exits.
enum StorageSelfTest {
    static func runHeadlessIfRequested() {
        guard ProcessInfo.processInfo.environment["MAILBACKUP_STORAGE_TEST"] != nil else { return }
        do {
            try run()
            print("STORAGE_OK")
            exit(0)
        } catch {
            print("STORAGE_FAIL \(error)")
            exit(1)
        }
    }

    private static func run() throws {
        let db = try Database()

        // Temporary archive root.
        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailBackupSelfTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: archiveRoot) }
        let store = ArchiveStore(root: archiveRoot)

        let account = Account(
            displayName: "Test", email: "t@example.com",
            imapHost: "imap.example.com", username: "t@example.com"
        )
        var folder = Folder(accountId: account.id, name: "INBOX")
        try db.writer.write { dbc in
            try account.insert(dbc)
            try folder.insert(dbc)
        }
        guard let folderId = folder.id else { throw fail("folder id not assigned") }

        // Write an .eml and an indexed message row.
        let raw = Data("From: Alice <alice@example.com>\r\nSubject: Quarterly report\r\n\r\nThe budget numbers are attached.".utf8)
        let relative = try store.writeEML(raw, accountId: account.id, folderName: folder.name, uid: 42)
        var message = Message(
            accountId: account.id, folderId: folderId, uid: 42,
            subject: "Quarterly report",
            fromName: "Alice", fromAddress: "alice@example.com",
            toAddresses: "bob@example.com",
            emlPath: relative,
            bodyText: "The budget numbers are attached.",
            snippet: "The budget numbers are attached."
        )
        try db.writer.write { dbc in try message.insert(dbc) }

        // Read the .eml back.
        let readBack = try store.readEML(relativePath: relative)
        guard readBack == raw else { throw fail(".eml roundtrip mismatch") }

        // FTS5 trigger should have indexed the row.
        let hits = try db.writer.read { dbc in
            try Int.fetchOne(
                dbc,
                sql: """
                SELECT COUNT(*) FROM message
                JOIN message_fts ON message_fts.rowid = message.id
                WHERE message_fts MATCH ?
                """,
                arguments: ["budget"]
            ) ?? 0
        }
        guard hits == 1 else { throw fail("FTS match returned \(hits), expected 1") }

        // Paging: insert 150 more (151 total) and verify offset pages.
        let repository = Repository(database: db)
        for uid in 1000..<1150 {
            try repository.insertMessage(
                Message(accountId: account.id, folderId: folderId, uid: uid, emlPath: "p/\(uid).eml")
            )
        }
        let page0 = try repository.messages(folderId: folderId, limit: 100, offset: 0)
        let page1 = try repository.messages(folderId: folderId, limit: 100, offset: 100)
        guard page0.count == 100, page1.count == 51 else {
            throw fail("paging counts \(page0.count)/\(page1.count), expected 100/51")
        }
        guard Set(page0.map(\.uid)).isDisjoint(with: Set(page1.map(\.uid))) else {
            throw fail("paging pages overlap")
        }

        // Keychain roundtrip.
        let secret = "app-password-\(UUID().uuidString)"
        try Keychain.setPassword(secret, account: account.id)
        defer { try? Keychain.deletePassword(account: account.id) }
        guard try Keychain.password(account: account.id) == secret else {
            throw fail("Keychain roundtrip mismatch")
        }
    }

    private static func fail(_ message: String) -> Error {
        NSError(domain: "StorageSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
