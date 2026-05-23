import Foundation
import GRDB

/// Archived email metadata. The full message lives on disk as `.eml`
/// (`emlPath`, relative to the archive root); this row is the searchable index.
struct Message: Identifiable, Codable, Equatable {
    var id: Int64?
    var accountId: String
    var folderId: Int64
    var uid: Int
    var messageId: String?      // RFC822 Message-ID header
    var subject: String?
    var fromName: String?
    var fromAddress: String?
    var toAddresses: String?
    var ccAddresses: String?
    var date: Date?             // Date header (sent time)
    var internalDate: Date?     // IMAP INTERNALDATE (server receive time)
    var size: Int?
    var flags: String?          // space-separated IMAP flags
    var hasAttachments: Bool
    var emlPath: String         // relative to archive root
    var bodyText: String?       // extracted plaintext, for full-text search
    var snippet: String?        // short preview for the message list
    var hasBody: Bool           // false until the .eml body has been downloaded
    var createdAt: Date

    init(
        id: Int64? = nil,
        accountId: String,
        folderId: Int64,
        uid: Int,
        messageId: String? = nil,
        subject: String? = nil,
        fromName: String? = nil,
        fromAddress: String? = nil,
        toAddresses: String? = nil,
        ccAddresses: String? = nil,
        date: Date? = nil,
        internalDate: Date? = nil,
        size: Int? = nil,
        flags: String? = nil,
        hasAttachments: Bool = false,
        emlPath: String,
        bodyText: String? = nil,
        snippet: String? = nil,
        hasBody: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.folderId = folderId
        self.uid = uid
        self.messageId = messageId
        self.subject = subject
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toAddresses = toAddresses
        self.ccAddresses = ccAddresses
        self.date = date
        self.internalDate = internalDate
        self.size = size
        self.flags = flags
        self.hasAttachments = hasAttachments
        self.emlPath = emlPath
        self.bodyText = bodyText
        self.snippet = snippet
        self.hasBody = hasBody
        self.createdAt = createdAt
    }
}

extension Message: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "message"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Columns needed to render lists — everything except the large `bodyText`
    /// (which is only needed for the FTS index). Fetching without it keeps the
    /// message list and search fast. `bodyText` decodes to nil when omitted.
    static let listColumnNames = [
        "id", "accountId", "folderId", "uid", "messageId", "subject",
        "fromName", "fromAddress", "toAddresses", "ccAddresses", "date",
        "internalDate", "size", "flags", "hasAttachments", "emlPath",
        "snippet", "hasBody", "createdAt",
    ]

    static var listColumns: [Column] { listColumnNames.map { Column($0) } }
}
