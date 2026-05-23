import Foundation

/// Development smoke test for import, run via `MAILBACKUP_IMPORT_TEST=1 ./MailBackup`.
enum ImportSelfTest {
    static func runHeadlessIfRequested() {
        guard ProcessInfo.processInfo.environment["MAILBACKUP_IMPORT_TEST"] != nil else { return }
        do {
            try run()
            print("IMPORT_OK")
            exit(0)
        } catch {
            print("IMPORT_FAIL \(error)")
            exit(1)
        }
    }

    private static func run() throws {
        let mbox = """
        From alice@example.com Mon Jan  1 00:00:00 2024
        From: Alice <alice@example.com>
        Subject: First

        Hello one
        From bob@example.com Tue Jan  2 00:00:00 2024
        From: Bob <bob@example.com>
        Subject: Second

        Hello two
        """

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailBackupImportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("test.mbox")
        try Data(mbox.utf8).write(to: url)

        let raws = try Importer.rawMessages(from: url)
        guard raws.count == 2 else { throw fail("rawMessages returned \(raws.count), expected 2") }

        let db = try Database()
        let repository = Repository(database: db)
        let store = ArchiveStore(root: dir.appendingPathComponent("archive", isDirectory: true))
        let account = Account(displayName: "Local", email: "l@local", imapHost: "", username: "", isLocal: true)
        try repository.saveAccount(account)
        let folder = try repository.upsertFolder(Folder(accountId: account.id, name: "test"))
        guard let folderId = folder.id else { throw fail("no folder id") }

        var uid = 1
        for raw in raws {
            let message = try Importer.makeMessage(
                from: raw, accountId: account.id, folderId: folderId,
                folderName: "test", uid: uid, store: store
            )
            try repository.insertMessage(message)
            uid += 1
        }

        let stored = try repository.messages(folderId: folderId, limit: 10)
        guard stored.count == 2 else { throw fail("inserted \(stored.count), expected 2") }
        let subjects = Set(stored.compactMap(\.subject))
        guard subjects == ["First", "Second"] else { throw fail("subjects: \(subjects)") }
        guard stored.contains(where: { $0.fromAddress == "alice@example.com" }) else {
            throw fail("from address not parsed")
        }
    }

    private static func fail(_ message: String) -> Error {
        NSError(domain: "ImportSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
