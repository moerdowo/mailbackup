import Foundation

/// Exports archived messages as standalone `.eml` files or a zipped EML archive.
enum Exporter {
    static func writeEML(message: Message, store: ArchiveStore, to url: URL) throws {
        let data = try store.readEML(relativePath: message.emlPath)
        try data.write(to: url, options: .atomic)
    }

    /// Writes the given messages into a temporary folder and zips it to `destination`.
    static func zip(messages: [Message], store: ArchiveStore, folderName: String, to destination: URL) throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailBackupExport-\(UUID().uuidString)", isDirectory: true)
        let payload = workspace.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        var usedNames = Set<String>()
        for message in messages {
            guard let data = try? store.readEML(relativePath: message.emlPath) else { continue }
            var name = filename(for: message)
            while usedNames.contains(name) {
                name = "\(UUID().uuidString.prefix(4))-\(name)"
            }
            usedNames.insert(name)
            try? data.write(to: payload.appendingPathComponent(name), options: .atomic)
        }

        try zipDirectory(payload, to: destination)
    }

    static func filename(for message: Message) -> String {
        let subjectPart = sanitize(String((message.subject ?? "message").prefix(60)))
        let base = subjectPart.isEmpty ? "message" : subjectPart
        return "\(message.uid)-\(base).eml"
    }

    /// Zips a directory using NSFileCoordinator's `.forUploading` option, which
    /// produces a standard zip archive without any third-party dependency.
    private static func zipDirectory(_ directory: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationError: Error?

        coordinator.coordinate(readingItemAt: directory, options: [.forUploading], error: &coordinationError) { zippedURL in
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: zippedURL, to: destination)
            } catch {
                operationError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\r\n\t")
        return name.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
    }
}
