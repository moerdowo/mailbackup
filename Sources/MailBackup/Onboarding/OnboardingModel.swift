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
    var providerNote: String?

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
    var didStartSync = false
    var setupError: String?
    private var savedAccount: Account?

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
        providerNote = provider.note
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

    /// Saves the account and kicks off the initial sync as an app-level
    /// background task, then advances to the sync step. The user can keep using
    /// the app while it runs.
    func startInitialSync() {
        guard !didStartSync else { return }
        setupError = nil

        if let path = customArchivePath {
            app.setArchiveRoot(URL(fileURLWithPath: path, isDirectory: true))
        }

        let account = draftAccount
        do {
            try app.addAccount(account, password: password)
        } catch {
            setupError = error.localizedDescription
            return
        }
        savedAccount = account
        didStartSync = true
        step = .sync
        app.startSync([SyncJob(account: account, folderNames: selectedFolders.sorted())])
    }

    func retryInitialSync() {
        guard let account = savedAccount else { return }
        app.startSync([SyncJob(account: account, folderNames: selectedFolders.sorted())])
    }
}
