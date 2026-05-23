import Foundation
import CryptoKit

/// Development smoke test for archive encryption, run via
/// `MAILBACKUP_CRYPTO_TEST=1 ./MailBackup`.
enum EncryptionSelfTest {
    static func runHeadlessIfRequested() {
        guard ProcessInfo.processInfo.environment["MAILBACKUP_CRYPTO_TEST"] != nil else { return }
        do {
            try run()
            print("CRYPTO_OK")
            exit(0)
        } catch {
            print("CRYPTO_FAIL \(error)")
            exit(1)
        }
    }

    private static func run() throws {
        let key = SymmetricKey(size: .bits256)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MailBackupCryptoTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let raw = Data("Subject: secret\r\n\r\nthe body".utf8)
        let plainStore = ArchiveStore(root: dir)
        let rel = try plainStore.writeEML(raw, accountId: "a", folderName: "INBOX", uid: 1)

        // Encrypt existing files.
        ArchiveConverter.convert(root: dir, key: key, encrypt: true)
        let onDisk = try Data(contentsOf: plainStore.url(forRelativePath: rel))
        guard ArchiveCrypto.isEncrypted(onDisk) else { throw fail("file not encrypted after convert") }

        // Encrypted store transparently decrypts on read.
        let encStore = ArchiveStore(root: dir, encryptionKey: key, encryptWrites: true)
        guard try encStore.readEML(relativePath: rel) == raw else { throw fail("decrypt roundtrip mismatch") }

        // Writing through the encrypted store encrypts on disk.
        let rel2 = try encStore.writeEML(raw, accountId: "a", folderName: "INBOX", uid: 2)
        let onDisk2 = try Data(contentsOf: encStore.url(forRelativePath: rel2))
        guard ArchiveCrypto.isEncrypted(onDisk2), try encStore.readEML(relativePath: rel2) == raw else {
            throw fail("encrypted write/read mismatch")
        }

        // Decrypt back to plaintext.
        ArchiveConverter.convert(root: dir, key: key, encrypt: false)
        let onDisk3 = try Data(contentsOf: plainStore.url(forRelativePath: rel))
        guard !ArchiveCrypto.isEncrypted(onDisk3), onDisk3 == raw else { throw fail("decrypt convert mismatch") }
    }

    private static func fail(_ message: String) -> Error {
        NSError(domain: "EncryptionSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
