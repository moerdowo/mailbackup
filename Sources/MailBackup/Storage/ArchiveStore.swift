import Foundation

/// Reads and writes raw `.eml` files (and extracted attachments) on disk.
/// Layout: `<root>/<accountId>/<sanitized folder>/<uid>.eml`.
struct ArchiveStore {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func relativePath(accountId: String, folderName: String, uid: Int) -> String {
        "\(accountId)/\(Self.sanitize(folderName))/\(uid).eml"
    }

    func emlURL(accountId: String, folderName: String, uid: Int) -> URL {
        root.appendingPathComponent(relativePath(accountId: accountId, folderName: folderName, uid: uid))
    }

    func url(forRelativePath relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    /// Writes a raw RFC822 message to disk and returns its path relative to `root`.
    @discardableResult
    func writeEML(_ data: Data, accountId: String, folderName: String, uid: Int) throws -> String {
        let relative = relativePath(accountId: accountId, folderName: folderName, uid: uid)
        let fileURL = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        return relative
    }

    func readEML(relativePath: String) throws -> Data {
        try Data(contentsOf: url(forRelativePath: relativePath))
    }

    func deleteEML(relativePath: String) throws {
        let fileURL = url(forRelativePath: relativePath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Makes a folder name safe to use as a single path component.
    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "_" : cleaned
    }
}
