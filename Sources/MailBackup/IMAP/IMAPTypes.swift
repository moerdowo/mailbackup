import Foundation

enum IMAPError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case commandFailed(String)
    case authenticationFailed(String)
    case fatal(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the server."
        case .connectionFailed(let m): return "Connection failed: \(m)"
        case .commandFailed(let m): return m
        case .authenticationFailed(let m): return "Authentication failed: \(m)"
        case .fatal(let m): return "Server error: \(m)"
        }
    }
}

/// A mailbox returned by LIST.
struct MailboxEntry: Identifiable, Hashable {
    var name: String       // full IMAP mailbox path
    var selectable: Bool
    var id: String { name }
}

/// Result of selecting a mailbox.
struct SelectResult {
    var exists: Int
    var uidValidity: Int?
    var uidNext: Int?
}

/// A single message fetched from the server, including its raw RFC822 bytes.
struct FetchedMessage {
    var uid: Int
    var flags: [String]
    var internalDate: Date?
    var size: Int?
    var rawData: Data
    var subject: String?
    var fromName: String?
    var fromAddress: String?
    var toAddresses: String?
    var ccAddresses: String?
    var sentDate: Date?
    var messageID: String?
}
