import Foundation
import Observation

/// Drives the multi-step onboarding wizard and holds the in-progress account.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome
        case account
        case folders
        case options
        case sync
    }

    var step: Step = .welcome

    // Account details
    var displayName = ""
    var email = ""
    var host = ""
    var port = "993"
    var security: ConnectionSecurity = .ssl
    var username = ""
    var password = ""

    // Connect + folder loading
    var isLoadingFolders = false
    var foldersError: String?
    var mailboxes: [MailboxEntry] = []
    var selectedFolders: Set<String> = []

    // Options
    var downloadAttachments = true
    var syncInterval: SyncInterval = .manual
    var customArchivePath: String?

    // Initial sync
    var isSyncing = false
    var syncError: String?
    var progress: SyncProgress?
    var isDone = false

    let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var canContinueFromAccount: Bool {
        !email.isEmpty && !host.isEmpty && !password.isEmpty && (Int(port) != nil)
    }

    func applyPreset(_ provider: MailProvider) {
        host = provider.host
        port = String(provider.port)
        security = provider.security
    }

    var draftAccount: Account {
        Account(
            displayName: displayName.isEmpty ? email : displayName,
            email: email,
            imapHost: host,
            imapPort: Int(port) ?? 993,
            security: security,
            username: username.isEmpty ? email : username,
            downloadAttachments: downloadAttachments,
            syncIntervalMinutes: syncInterval.minutes,
            archivePath: customArchivePath
        )
    }

    /// Tests the connection by logging in and listing folders, then advances.
    func connectAndLoadFolders() async {
        isLoadingFolders = true
        foldersError = nil
        do {
            let entries = try await app.syncEngine.listFolders(account: draftAccount, password: password)
            mailboxes = entries.filter(\.selectable).sorted { $0.name.lowercased() < $1.name.lowercased() }
            if selectedFolders.isEmpty {
                selectedFolders = Set(mailboxes.map(\.name))
            }
            step = .folders
        } catch {
            foldersError = error.localizedDescription
        }
        isLoadingFolders = false
    }

    func startInitialSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        step = .sync

        if let path = customArchivePath {
            app.setArchiveRoot(URL(fileURLWithPath: path, isDirectory: true))
        }

        let account = draftAccount
        let folders = selectedFolders.sorted()
        do {
            try app.addAccount(account, password: password)
            try await app.syncEngine.sync(
                account: account,
                password: password,
                folderNames: folders
            ) { progress in
                Task { @MainActor in self.progress = progress }
            }
            isDone = true
        } catch is CancellationError {
            syncError = "Sync was cancelled."
        } catch {
            syncError = error.localizedDescription
        }
        isSyncing = false
    }
}
