import Foundation
import GRDB

/// Transport security for an IMAP connection.
enum ConnectionSecurity: String, Codable, CaseIterable, DatabaseValueConvertible {
    case ssl       // implicit TLS, typically port 993
    case startTLS  // upgrade plaintext to TLS, typically port 143
    case none      // plaintext, typically port 143

    var displayName: String {
        switch self {
        case .ssl: return "SSL/TLS"
        case .startTLS: return "STARTTLS"
        case .none: return "None"
        }
    }
}

/// An IMAP account being archived. Passwords are NOT stored here; they live in
/// the Keychain keyed by `id`.
struct Account: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var email: String
    var imapHost: String
    var imapPort: Int
    var security: ConnectionSecurity
    var username: String
    var downloadAttachments: Bool
    var syncIntervalMinutes: Int?  // nil = manual only
    var archivePath: String?       // nil = default archive root
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        displayName: String,
        email: String,
        imapHost: String,
        imapPort: Int = 993,
        security: ConnectionSecurity = .ssl,
        username: String,
        downloadAttachments: Bool = true,
        syncIntervalMinutes: Int? = nil,
        archivePath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.security = security
        self.username = username
        self.downloadAttachments = downloadAttachments
        self.syncIntervalMinutes = syncIntervalMinutes
        self.archivePath = archivePath
        self.createdAt = createdAt
    }
}

extension Account: FetchableRecord, PersistableRecord {
    static let databaseTableName = "account"
}
