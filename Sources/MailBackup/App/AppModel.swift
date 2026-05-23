import Foundation
import Observation

/// Root application state: owns the database, repository, archive store, and
/// sync engine, and tracks the configured accounts.
@MainActor
@Observable
final class AppModel {
    private(set) var accounts: [Account] = []
    var loadError: String?

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
}
