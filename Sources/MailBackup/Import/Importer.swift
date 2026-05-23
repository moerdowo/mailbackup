import Foundation

/// Parses `.mbox`, `.eml`, and ZIP-of-`.eml` files into messages for import.
enum Importer {
    /// Returns the raw RFC822 messages contained in a file.
    static func rawMessages(from url: URL) throws -> [Data] {
        switch url.pathExtension.lowercased() {
        case "mbox":
            return MailHeaders.splitMbox(try Data(contentsOf: url))
        case "eml":
            return [try Data(contentsOf: url)]
        case "zip":
            return try emlMessagesFromZip(url)
        default:
            let data = try Data(contentsOf: url)
            return data.starts(with: Array("From ".utf8)) ? MailHeaders.splitMbox(data) : [data]
        }
    }

    /// Builds and persists a `Message` for one raw RFC822 blob.
    static func makeMessage(
        from raw: Data,
        accountId: String,
        folderId: Int64,
        folderName: String,
        uid: Int,
        store: ArchiveStore
    ) throws -> Message {
        let relativePath = try store.writeEML(raw, accountId: accountId, folderName: folderName, uid: uid)
        let mime = MIMEMessage(data: raw)
        let headers = mime.root.headers
        let (fromName, fromAddress) = MailHeaders.address(from: headers["from"] ?? "")

        return Message(
            accountId: accountId,
            folderId: folderId,
            uid: uid,
            messageId: headers["message-id"],
            subject: headers["subject"].map { RFC2047.decode($0) },
            fromName: fromName,
            fromAddress: fromAddress,
            toAddresses: headers["to"].map { RFC2047.decode($0) },
            ccAddresses: headers["cc"].map { RFC2047.decode($0) },
            date: MailHeaders.parseDate(headers["date"] ?? ""),
            internalDate: nil,
            size: raw.count,
            flags: nil,
            hasAttachments: mime.hasAttachments,
            emlPath: relativePath,
            bodyText: mime.plainText,
            snippet: mime.snippet()
        )
    }

    private static func emlMessagesFromZip(_ url: URL) throws -> [Data] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailBackupImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // `ditto -x -k` extracts a zip archive on macOS without a third-party dep.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var messages: [Data] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "eml" {
            if let data = try? Data(contentsOf: fileURL) { messages.append(data) }
        }
        return messages
    }
}
