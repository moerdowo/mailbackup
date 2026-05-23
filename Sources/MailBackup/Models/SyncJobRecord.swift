import Foundation

/// A record of a single account's sync run, shown in the Jobs view.
struct SyncJobRecord: Identifiable {
    enum Status: String {
        case queued = "Queued"
        case running = "Running"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }

    let id: UUID
    let accountEmail: String
    let folderNames: [String]
    var status: Status
    var startedAt: Date?
    var finishedAt: Date?
    var messagesArchived: Int
    var progress: SyncProgress?
    var error: String?

    init(accountEmail: String, folderNames: [String]) {
        id = UUID()
        self.accountEmail = accountEmail
        self.folderNames = folderNames
        status = .queued
        messagesArchived = 0
    }
}
