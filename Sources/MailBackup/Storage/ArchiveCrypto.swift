import Foundation
import CryptoKit

/// AES-GCM encryption for `.eml` files at rest. Encrypted files carry a small
/// magic header so plaintext and encrypted files can coexist (and decrypt only
/// happens when a file is actually encrypted).
enum ArchiveCrypto {
    private static let magic = Array("MBENC1\n".utf8)

    static func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    static func encrypt(_ data: Data, key: SymmetricKey) -> Data {
        guard let sealed = try? AES.GCM.seal(data, using: key), let combined = sealed.combined else {
            return data
        }
        return Data(magic) + combined
    }

    static func decrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        guard isEncrypted(data) else { return data }
        let ciphertext = data.dropFirst(magic.count)
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    /// The archive key, stored as base64 in the Keychain. Created on first use.
    private static let keychainAccount = "archive-encryption-key"

    static func existingKey() -> SymmetricKey? {
        guard let base64 = try? Keychain.password(account: keychainAccount),
              let raw = Data(base64Encoded: base64) else { return nil }
        return SymmetricKey(data: raw)
    }

    static func getOrCreateKey() -> SymmetricKey? {
        if let key = existingKey() { return key }
        let key = SymmetricKey(size: .bits256)
        let base64 = key.withUnsafeBytes { Data(Array($0)).base64EncodedString() }
        try? Keychain.setPassword(base64, account: keychainAccount)
        return existingKey()
    }
}

/// Converts every file under the archive root to/from encrypted form.
enum ArchiveConverter {
    static func convert(root: URL, key: SymmetricKey, encrypt: Bool) {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let alreadyEncrypted = ArchiveCrypto.isEncrypted(data)
            if encrypt == alreadyEncrypted { continue }  // already in target form

            let plain = alreadyEncrypted ? ((try? ArchiveCrypto.decrypt(data, key: key)) ?? data) : data
            let out = encrypt ? ArchiveCrypto.encrypt(plain, key: key) : plain
            try? out.write(to: url, options: .atomic)
        }
    }
}
