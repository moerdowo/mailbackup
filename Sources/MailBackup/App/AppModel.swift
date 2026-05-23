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

    /// Global pause: when true, no syncs run and any running sync is stopped.
    private(set) var isPaused: Bool = UserDefaults.standard.bool(forKey: AppModel.pausedKey)
    static let pausedKey = "syncPaused"
    private var scheduleTimer: Timer?

    /// Sync run records (newest first), shown in the Jobs view.
    private(set) var jobs: [SyncJobRecord] = []
    private let maxJobs = 200

    /// Persistent activity log, shown in the Log view.
    let activityLog = ActivityLog()

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
        startScheduler()
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
        activityLog.log("Added account \(account.email)", category: "Account")
        reloadAccounts()
    }

    func deleteAccount(_ account: Account) {
        try? repository.deleteAccount(id: account.id)
        try? Keychain.deletePassword(account: account.id)
        // Remove the account's on-disk archive (root/<accountId>/...).
        let directory = archiveStore.root.appendingPathComponent(account.id, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        jobs.removeAll { $0.accountEmail == account.email }
        activityLog.log("Removed account \(account.email) and its local archive", category: "Account", level: .warning)
        reloadAccounts()
        dataRevision &+= 1
    }

    /// Updates an account's settings and, if a non-empty password is provided,
    /// its stored credential.
    func updateAccount(_ account: Account, newPassword: String?) {
        try? repository.saveAccount(account)
        if let newPassword, !newPassword.isEmpty {
            try? Keychain.setPassword(newPassword, account: account.id)
        }
        activityLog.log("Updated settings for \(account.email)", category: "Account")
        reloadAccounts()
    }

    func setAccountPaused(_ account: Account, paused: Bool) {
        var updated = account
        updated.isPaused = paused
        try? repository.saveAccount(updated)
        activityLog.log("\(paused ? "Paused" : "Resumed") syncing for \(account.email)", category: "Account")
        reloadAccounts()
    }

    /// Reconciles the set of folders archived for an account: creates rows for
    /// newly selected folders and deletes deselected ones (rows, messages, files).
    func applyFolderSelection(account: Account, selectedNames: Set<String>) {
        let existing = (try? repository.folders(accountId: account.id)) ?? []
        let existingNames = Set(existing.map(\.name))

        for folder in existing where !selectedNames.contains(folder.name) {
            if let id = folder.id {
                try? repository.deleteMessages(folderId: id)
                try? repository.deleteFolder(id: id)
            }
            let directory = archiveStore.root
                .appendingPathComponent(account.id, isDirectory: true)
                .appendingPathComponent(ArchiveStore.sanitize(folder.name), isDirectory: true)
            try? FileManager.default.removeItem(at: directory)
        }
        for name in selectedNames where !existingNames.contains(name) {
            _ = try? repository.upsertFolder(Folder(accountId: account.id, name: name))
        }
        activityLog.log("Updated archived folders for \(account.email)", category: "Account")
        reloadAccounts()
        dataRevision &+= 1
    }

    func password(for account: Account) -> String? {
        try? Keychain.password(account: account.id)
    }

    // MARK: - Background sync

    /// Syncs every (non-paused) account using its already-archived folders.
    func startSyncAllAccounts() {
        let jobs = accounts.filter { !$0.isPaused }.compactMap { account -> SyncJob? in
            let names = ((try? repository.folders(accountId: account.id)) ?? []).map(\.name)
            return names.isEmpty ? nil : SyncJob(account: account, folderNames: names)
        }
        startSync(jobs)
    }

    /// Syncs a single account using its archived folders.
    func syncAccount(_ account: Account) {
        guard !account.isPaused else { return }
        let names = ((try? repository.folders(accountId: account.id)) ?? []).map(\.name)
        startSync([SyncJob(account: account, folderNames: names)])
    }

    // MARK: - Pause

    func setPaused(_ paused: Bool) {
        isPaused = paused
        UserDefaults.standard.set(paused, forKey: AppModel.pausedKey)
        if paused {
            cancelSync()
            activityLog.log("Syncing paused", category: "Sync", level: .warning)
        } else {
            activityLog.log("Syncing resumed", category: "Sync")
        }
    }

    // MARK: - Scheduler

    private func startScheduler() {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runDueSyncs() }
        }
    }

    /// Triggers syncs for accounts whose sync interval has elapsed.
    private func runDueSyncs() {
        guard !isPaused, !isSyncing else { return }
        let now = Date()
        let due = accounts.filter { !$0.isPaused }.compactMap { account -> SyncJob? in
            guard let interval = account.syncIntervalMinutes else { return nil }
            let folders = (try? repository.folders(accountId: account.id)) ?? []
            guard !folders.isEmpty else { return nil }
            let lastSynced = folders.compactMap(\.lastSyncedAt).max()
            if let last = lastSynced, now.timeIntervalSince(last) < Double(interval) * 60 { return nil }
            return SyncJob(account: account, folderNames: folders.map(\.name))
        }
        if !due.isEmpty { startSync(due) }
    }

    /// Starts a background sync for the given jobs. No-op if one is running or
    /// syncing is globally paused.
    func startSync(_ syncJobs: [SyncJob]) {
        guard !isPaused, !isSyncing, !syncJobs.isEmpty else { return }
        isSyncing = true
        syncError = nil
        syncProgress = nil

        let records = syncJobs.map {
            SyncJobRecord(accountEmail: $0.account.email, folderNames: $0.folderNames)
        }
        jobs.insert(contentsOf: records, at: 0)
        if jobs.count > maxJobs { jobs.removeLast(jobs.count - maxJobs) }

        let ids = records.map(\.id)
        syncTask = Task { [weak self] in
            await self?.runSync(syncJobs, recordIDs: ids)
        }
    }

    func cancelSync() {
        syncTask?.cancel()
    }

    func clearFinishedJobs() {
        jobs.removeAll { $0.status != .running && $0.status != .queued }
    }

    private func runSync(_ syncJobs: [SyncJob], recordIDs: [UUID]) async {
        defer {
            isSyncing = false
            syncProgress = nil
            syncStatusText = nil
            reloadAccounts()
            dataRevision &+= 1
            syncTask = nil
        }

        for (index, job) in syncJobs.enumerated() {
            let recordID = recordIDs[index]
            if Task.isCancelled {
                updateJob(recordID) { $0.status = .cancelled; $0.finishedAt = Date() }
                continue
            }
            guard let password = password(for: job.account) else {
                let message = "No saved password for \(job.account.email)."
                syncError = message
                updateJob(recordID) { $0.status = .failed; $0.error = message; $0.finishedAt = Date() }
                activityLog.log(message, category: "Sync", level: .error)
                continue
            }

            let before = (try? repository.messageCount(accountId: job.account.id)) ?? 0
            updateJob(recordID) { $0.status = .running; $0.startedAt = Date() }
            activityLog.log("Sync started for \(job.account.email)", category: "Sync")

            do {
                try await syncEngine.sync(
                    account: job.account,
                    password: password,
                    folderNames: job.folderNames
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.noteProgress(progress, account: job.account)
                        self?.updateJob(recordID) { $0.progress = progress }
                    }
                }
                let after = (try? repository.messageCount(accountId: job.account.id)) ?? before
                let archived = max(0, after - before)
                updateJob(recordID) {
                    $0.status = .completed
                    $0.finishedAt = Date()
                    $0.messagesArchived = archived
                    $0.progress = nil
                }
                activityLog.log("Synced \(job.account.email): \(archived) new message\(archived == 1 ? "" : "s")", category: "Sync")
            } catch is CancellationError {
                syncError = "Sync was cancelled."
                updateJob(recordID) { $0.status = .cancelled; $0.finishedAt = Date(); $0.progress = nil }
                activityLog.log("Sync cancelled for \(job.account.email)", category: "Sync", level: .warning)
            } catch {
                syncError = "Sync failed for \(job.account.email): \(error.localizedDescription)"
                updateJob(recordID) { $0.status = .failed; $0.error = error.localizedDescription; $0.finishedAt = Date(); $0.progress = nil }
                activityLog.log("Sync failed for \(job.account.email): \(error.localizedDescription)", category: "Sync", level: .error)
            }
        }
    }

    private func updateJob(_ id: UUID, _ mutate: (inout SyncJobRecord) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
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
