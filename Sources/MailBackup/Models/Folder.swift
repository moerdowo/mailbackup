import Foundation
import GRDB

/// An IMAP mailbox/folder belonging to an account.
struct Folder: Identifiable, Codable, Equatable {
    var id: Int64?
    var accountId: String
    var name: String            // full IMAP mailbox path, e.g. "INBOX", "[Gmail]/Sent Mail"
    var uidValidity: Int?       // IMAP UIDVALIDITY; a change invalidates stored UIDs
    var uidNext: Int?           // last seen UIDNEXT
    var lastSyncedAt: Date?

    init(
        id: Int64? = nil,
        accountId: String,
        name: String,
        uidValidity: Int? = nil,
        uidNext: Int? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.uidValidity = uidValidity
        self.uidNext = uidNext
        self.lastSyncedAt = lastSyncedAt
    }
}

extension Folder: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "folder"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
