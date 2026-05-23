import Foundation
import Observation

/// A single account + the folders to sync for it.
struct SyncJob: Sendable {
    let account: Account
    let folderNames: [String]
}

/// Root application state: owns the database, repository, archive store, and
/// sync engine, and tracks the configured accounts.
@MainActor
@Observable
final class AppModel {
    private(set) var accounts: [Account] = []
    var loadError: String?

    // Background sync state. Sync runs in a task owned here (not by any view),
    // so it survives navigation and onboarding dismissal.
    private(set) var isSyncing = false
    private(set) var syncProgress: SyncProgress?
    private(set) var syncStatusText: String?
    var syncError: String?
    /// Bumped (throttled) whenever archived data changes, so views can refresh.
    private(set) var dataRevision = 0
    private var syncTask: Task<Void, Never>?
    private var lastRevisionBump = Date.distantPast

    let database: Database
    let repository: Repository
    private(set) var archiveRoot: URL
    private(set) var archiveStore: ArchiveStore
    private(set) var syncEngine: SyncEngine

    init() {
        let database: Database
        var loadError: String?
        do {
            database = try Database.makeDefault()
        } catch {
            loadError = "Could not open the archive database: \(error.localizedDescription)"
            database = try! Database()  // in-memory fallback so the app still launches
        }
        let repository = Repository(database: database)
        let resolvedRoot: URL
        if let stored = UserDefaults.standard.string(forKey: AppModel.archiveRootKey) {
            resolvedRoot = URL(fileURLWithPath: stored, isDirectory: true)
        } else {
            resolvedRoot = (try? AppPaths.defaultArchiveRoot()) ?? FileManager.default.temporaryDirectory
        }
        let store = ArchiveStore(root: resolvedRoot)

        self.database = database
        self.loadError = loadError
        self.repository = repository
        self.archiveRoot = resolvedRoot
        self.archiveStore = store
        self.syncEngine = SyncEngine(repository: repository, archiveStore: store)
        self.accounts = (try? repository.allAccounts()) ?? []
    }

    static let archiveRootKey = "archiveRoot"

    var hasAccounts: Bool { !accounts.isEmpty }

    func reloadAccounts() {
        accounts = (try? repository.allAccounts()) ?? []
    }

    func setArchiveRoot(_ url: URL) {
        archiveRoot = url
        archiveStore = ArchiveStore(root: url)
        syncEngine = SyncEngine(repository: repository, archiveStore: archiveStore)
        UserDefaults.standard.set(url.path, forKey: AppModel.archiveRootKey)
    }

    func addAccount(_ account: Account, password: String) throws {
        try Keychain.setPassword(password, account: account.id)
        try repository.saveAccount(account)
        reloadAccounts()
    }

    func deleteAccount(_ account: Account) {
        try? repository.deleteAccount(id: account.id)
        try? Keychain.deletePassword(account: account.id)
        reloadAccounts()
    }

    func password(for account: Account) -> String? {
        try? Keychain.password(account: account.id)
    }

    // MARK: - Background sync

    /// Syncs every account using its already-archived folders.
    func startSyncAllAccounts() {
        let jobs = accounts.compactMap { account -> SyncJob? in
            let names = ((try? repository.folders(accountId: account.id)) ?? []).map(\.name)
            return names.isEmpty ? nil : SyncJob(account: account, folderNames: names)
        }
        startSync(jobs)
    }

    /// Starts a background sync for the given jobs. No-op if one is running.
    func startSync(_ jobs: [SyncJob]) {
        guard !isSyncing, !jobs.isEmpty else { return }
        isSyncing = true
        syncError = nil
        syncProgress = nil
        syncTask = Task { [weak self] in
            await self?.runSync(jobs)
        }
    }

    func cancelSync() {
        syncTask?.cancel()
    }

    private func runSync(_ jobs: [SyncJob]) async {
        defer {
            isSyncing = false
            syncProgress = nil
            syncStatusText = nil
            reloadAccounts()
            dataRevision &+= 1
            syncTask = nil
        }

        for job in jobs {
            if Task.isCancelled { break }
            guard let password = password(for: job.account) else {
                syncError = "No saved password for \(job.account.email)."
                continue
            }
            do {
                try await syncEngine.sync(
                    account: job.account,
                    password: password,
                    folderNames: job.folderNames
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.noteProgress(progress, account: job.account)
                    }
                }
            } catch is CancellationError {
                syncError = "Sync was cancelled."
            } catch {
                syncError = "Sync failed for \(job.account.email): \(error.localizedDescription)"
            }
        }
    }

    private func noteProgress(_ progress: SyncProgress, account: Account) {
        syncProgress = progress
        let counts = progress.messagesTotal > 0 ? " (\(progress.messagesDone)/\(progress.messagesTotal))" : ""
        syncStatusText = "\(account.email): \(progress.phase)\(counts)"

        // Throttle data-change notifications so the UI can show newly archived
        // messages mid-sync without refreshing on every single message.
        let now = Date()
        if now.timeIntervalSince(lastRevisionBump) > 0.75 {
            lastRevisionBump = now
            reloadAccounts()
            dataRevision &+= 1
        }
    }
}
