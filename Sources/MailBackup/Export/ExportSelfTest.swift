import Foundation

/// Development smoke test for export, run via
/// `MAILBACKUP_EXPORT_TEST=1 ./MailBackup`.
enum ExportSelfTest {
    static func runHeadlessIfRequested() {
        guard ProcessInfo.processInfo.environment["MAILBACKUP_EXPORT_TEST"] != nil else { return }
        do {
            try run()
            print("EXPORT_OK")
            exit(0)
        } catch {
            print("EXPORT_FAIL \(error)")
            exit(1)
        }
    }

    private static func run() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailBackupExportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let archiveRoot = workspace.appendingPathComponent("archive", isDirectory: true)
        let store = ArchiveStore(root: archiveRoot)
        let accountId = "acct"
        let raw = Data("Subject: Hello\r\n\r\nBody text".utf8)
        let relative = try store.writeEML(raw, accountId: accountId, folderName: "INBOX", uid: 7)
        let message = Message(accountId: accountId, folderId: 1, uid: 7, subject: "Hello", emlPath: relative)

        // Single .eml export.
        let emlURL = workspace.appendingPathComponent("out.eml")
        try Exporter.writeEML(message: message, store: store, to: emlURL)
        guard try Data(contentsOf: emlURL) == raw else { throw err("eml roundtrip mismatch") }

        // Zip export.
        let zipURL = workspace.appendingPathComponent("out.zip")
        try Exporter.zip(messages: [message], store: store, folderName: "INBOX", to: zipURL)
        let zipData = try Data(contentsOf: zipURL)
        guard zipData.count > 4, Array(zipData.prefix(2)) == [0x50, 0x4B] else {
            throw err("zip missing PK signature (size=\(zipData.count))")
        }
    }

    private static func err(_ message: String) -> Error {
        NSError(domain: "ExportSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
