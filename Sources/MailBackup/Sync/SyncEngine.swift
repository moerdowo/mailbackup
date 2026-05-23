import Foundation

/// Progress update emitted during a sync run.
struct SyncProgress: Equatable {
    var phase: String
    var folderName: String
    var folderIndex: Int
    var folderCount: Int
    var messagesDone: Int
    var messagesTotal: Int
}

/// Orchestrates a sync: connects, logs in, and for each selected folder performs
/// an incremental UID-based fetch, writing `.eml` files and index rows.
final class SyncEngine {
    let repository: Repository
    let archiveStore: ArchiveStore

    init(repository: Repository, archiveStore: ArchiveStore) {
        self.repository = repository
        self.archiveStore = archiveStore
    }

    /// Fetches the selectable mailbox list for an account (used by onboarding's
    /// folder picker). Connects, logs in, lists, and disconnects.
    func listFolders(account: Account, password: String) async throws -> [MailboxEntry] {
        let client = IMAPClient()
        do {
            try await client.connect(host: account.imapHost, port: account.imapPort, security: account.security)
            try await client.login(username: account.username, password: password)
            let mailboxes = try await client.listMailboxes()
            await client.disconnect()
            return mailboxes
        } catch {
            await client.disconnect()
            throw error
        }
    }

    /// Syncs the given folders. `progress` is called on a background task; the
    /// caller is responsible for hopping to the main actor for UI updates.
    func sync(
        account: Account,
        password: String,
        folderNames: [String],
        progress: @escaping (SyncProgress) -> Void
    ) async throws {
        let client = IMAPClient()
        do {
            progress(SyncProgress(phase: "Connecting…", folderName: "", folderIndex: 0, folderCount: folderNames.count, messagesDone: 0, messagesTotal: 0))
            try await client.connect(host: account.imapHost, port: account.imapPort, security: account.security)
            try await client.login(username: account.username, password: password)

            for (offset, name) in folderNames.enumerated() {
                try Task.checkCancellation()
                let folderIndex = offset + 1
                progress(SyncProgress(phase: "Opening \(name)…", folderName: name, folderIndex: folderIndex, folderCount: folderNames.count, messagesDone: 0, messagesTotal: 0))

                let selection = try await client.select(mailbox: name)

                var folder = try repository.folder(accountId: account.id, name: name)
                    ?? Folder(accountId: account.id, name: name)
                if let stored = folder.uidValidity, let current = selection.uidValidity, stored != current,
                   let folderId = folder.id {
                    // UIDVALIDITY changed: stored UIDs are no longer valid.
                    try repository.deleteMessages(folderId: folderId)
                }
                folder.uidValidity = selection.uidValidity
                folder.uidNext = selection.uidNext
                folder = try repository.upsertFolder(folder)
                guard let folderId = folder.id else { continue }

                let serverUIDs = try await client.searchAllUIDs()
                let existing = try repository.existingUIDs(folderId: folderId)
                let toFetch = serverUIDs.filter { !existing.contains($0) }.sorted()

                for (done, uid) in toFetch.enumerated() {
                    try Task.checkCancellation()
                    let fetched = try await client.fetchMessage(uid: uid)
                    try store(fetched, account: account, folderId: folderId, folderName: name)
                    progress(SyncProgress(
                        phase: "Archiving \(name)…",
                        folderName: name,
                        folderIndex: folderIndex,
                        folderCount: folderNames.count,
                        messagesDone: done + 1,
                        messagesTotal: toFetch.count
                    ))
                }

                try repository.updateFolderState(
                    id: folderId,
                    uidValidity: selection.uidValidity,
                    uidNext: selection.uidNext,
                    lastSyncedAt: Date()
                )
            }

            await client.disconnect()
            progress(SyncProgress(phase: "Done", folderName: "", folderIndex: folderNames.count, folderCount: folderNames.count, messagesDone: 0, messagesTotal: 0))
        } catch {
            await client.disconnect()
            throw error
        }
    }

    private func store(_ fetched: FetchedMessage, account: Account, folderId: Int64, folderName: String) throws {
        let relativePath = try archiveStore.writeEML(
            fetched.rawData, accountId: account.id, folderName: folderName, uid: fetched.uid
        )
        let mime = MIMEMessage(data: fetched.rawData)
        let message = Message(
            accountId: account.id,
            folderId: folderId,
            uid: fetched.uid,
            messageId: fetched.messageID,
            subject: fetched.subject.map { RFC2047.decode($0) },
            fromName: fetched.fromName.map { RFC2047.decode($0) },
            fromAddress: fetched.fromAddress,
            toAddresses: fetched.toAddresses.map { RFC2047.decode($0) },
            ccAddresses: fetched.ccAddresses.map { RFC2047.decode($0) },
            date: fetched.sentDate,
            internalDate: fetched.internalDate,
            size: fetched.size,
            flags: fetched.flags.isEmpty ? nil : fetched.flags.joined(separator: " "),
            hasAttachments: mime.hasAttachments,
            emlPath: relativePath,
            bodyText: mime.plainText,
            snippet: mime.snippet()
        )
        try repository.insertMessage(message)
    }
}
