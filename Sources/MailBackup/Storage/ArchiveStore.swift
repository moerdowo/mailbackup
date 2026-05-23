import Foundation
import CryptoKit

/// Reads and writes raw `.eml` files (and extracted attachments) on disk.
/// Layout: `<root>/<accountId>/<sanitized folder>/<uid>.eml`.
/// When `encryptWrites` is set, new files are AES-GCM encrypted; reads
/// transparently decrypt any encrypted file when the key is available.
struct ArchiveStore {
    let root: URL
    var encryptionKey: SymmetricKey?
    var encryptWrites: Bool

    init(root: URL, encryptionKey: SymmetricKey? = nil, encryptWrites: Bool = false) {
        self.root = root
        self.encryptionKey = encryptionKey
        self.encryptWrites = encryptWrites
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
        let payload: Data
        if encryptWrites, let key = encryptionKey {
            payload = ArchiveCrypto.encrypt(data, key: key)
        } else {
            payload = data
        }
        try payload.write(to: fileURL, options: .atomic)
        return relative
    }

    func readEML(relativePath: String) throws -> Data {
        let raw = try Data(contentsOf: url(forRelativePath: relativePath))
        if let key = encryptionKey, ArchiveCrypto.isEncrypted(raw) {
            return try ArchiveCrypto.decrypt(raw, key: key)
        }
        return raw
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
