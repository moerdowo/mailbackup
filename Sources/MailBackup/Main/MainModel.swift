import Foundation
import Observation

struct MessageContent {
    var html: String?
    var plainText: String?
    var attachments: [MIMEMessage.Attachment]
}

/// What the sidebar has selected: the dashboard overview, global search across
/// all accounts, or a specific folder.
enum SidebarItem: Hashable {
    case dashboard
    case search
    case savedSearch(UUID)
    case jobs
    case log
    case folder(Int64)
}

@MainActor
@Observable
final class MainModel {
    let app: AppModel

    struct FolderNode: Identifiable {
        let folder: Folder
        let count: Int
        var id: Int64 { folder.id ?? -1 }
        var name: String { folder.name }
    }

    struct AccountNode: Identifiable {
        let account: Account
        var folders: [FolderNode]
        let total: Int
        let storageBytes: Int
        let lastSyncedAt: Date?
        var id: String { account.id }
    }

    var accountNodes: [AccountNode] = []
    var selection: SidebarItem? = .dashboard
    var selectedFolderId: Int64? {
        if case .folder(let id) = selection { return id }
        return nil
    }
    var isSearchMode: Bool {
        switch selection {
        case .search, .savedSearch: return true
        default: return false
        }
    }
    var messages: [Message] = []
    var selectedMessageId: Int64?
    var searchText = ""
    var filter = MessageFilter()
    var threaded = false
    var errorMessage: String?
    var exportStatus: String?

    // Paging
    let pageSize = 100
    var hasMoreMessages = false
    var searchTotal = 0
    var isSearching = false
    private var isLoadingPage = false
    private var searchTask: Task<Void, Never>?
    var isViewingFirstPage: Bool { messages.count <= pageSize }

    init(app: AppModel) {
        self.app = app
        reloadSidebar()
        refreshMessages()
    }

    func reloadSidebar() {
        var nodes: [AccountNode] = []
        for account in app.accounts {
            let folders = (try? app.repository.folders(accountId: account.id)) ?? []
            let counts = (try? app.repository.folderMessageCounts(accountId: account.id)) ?? [:]
            let folderNodes = folders.compactMap { folder -> FolderNode? in
                guard let id = folder.id else { return nil }
                return FolderNode(folder: folder, count: counts[id] ?? 0)
            }
            let total = counts.values.reduce(0, +)
            let storage = (try? app.repository.totalArchivedSize(accountId: account.id)) ?? 0
            let lastSynced = folderNodes.compactMap { $0.folder.lastSyncedAt }.max()
            nodes.append(AccountNode(account: account, folders: folderNodes, total: total, storageBytes: storage, lastSyncedAt: lastSynced))
        }
        accountNodes = nodes
    }

    var totalMessages: Int { accountNodes.reduce(0) { $0 + $1.total } }
    var totalStorageBytes: Int { accountNodes.reduce(0) { $0 + $1.storageBytes } }
    var totalFolders: Int { accountNodes.reduce(0) { $0 + $1.folders.count } }

    /// Refreshes the message list. Folder browsing is synchronous (indexed,
    /// fast); search is debounced and runs off the main thread so typing never
    /// blocks the UI.
    func refreshMessages() {
        searchTask?.cancel()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Folder browsing with no query: synchronous and fast.
        if !isSearchMode, trimmed.isEmpty, case .folder(let id) = selection {
            isSearching = false
            loadFolderFirstPage(folderId: id)
            return
        }

        // Need at least 2 characters to run a search (1-char prefix scans are
        // pathologically broad).
        guard trimmed.count >= 2 else {
            isSearching = false
            messages = []
            searchTotal = 0
            hasMoreMessages = false
            return
        }

        let scope: Int64? = { if case .folder(let id) = selection { return id }; return nil }()
        let currentFilter = filter
        let size = pageSize
        let repository = app.repository
        isSearching = true

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)  // debounce
            guard !Task.isCancelled, let self else { return }

            let results = (try? await Task.detached(priority: .userInitiated) {
                try repository.searchMessages(query: trimmed, folderId: scope, filter: currentFilter, limit: size, offset: 0)
            }.value) ?? []
            guard !Task.isCancelled else { return }

            self.messages = results
            self.hasMoreMessages = results.count == size
            self.isSearching = false
            if !results.contains(where: { $0.id == self.selectedMessageId }) {
                self.selectedMessageId = results.first?.id
            }

            // The count can be slower than the first page; update it separately.
            let count = (try? await Task.detached(priority: .utility) {
                try repository.searchMessageCount(query: trimmed, folderId: scope, filter: currentFilter)
            }.value) ?? results.count
            guard !Task.isCancelled else { return }
            self.searchTotal = count
        }
    }

    private func loadFolderFirstPage(folderId: Int64) {
        do {
            messages = try app.repository.messages(folderId: folderId, filter: filter, limit: pageSize, offset: 0)
            searchTotal = 0
            hasMoreMessages = messages.count == pageSize
            if !messages.contains(where: { $0.id == selectedMessageId }) {
                selectedMessageId = messages.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
            messages = []
            hasMoreMessages = false
        }
    }

    /// Appends the next page. Safe to call repeatedly (re-entrancy guarded).
    func loadMore() {
        guard hasMoreMessages, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = messages.count
        do {
            let next: [Message]
            switch selection {
            case .search, .savedSearch:
                next = trimmed.isEmpty ? [] : try app.repository.searchMessages(query: trimmed, filter: filter, limit: pageSize, offset: offset)
            case .folder(let id):
                if trimmed.isEmpty {
                    next = try app.repository.messages(folderId: id, filter: filter, limit: pageSize, offset: offset)
                } else {
                    next = try app.repository.searchMessages(query: trimmed, folderId: id, filter: filter, limit: pageSize, offset: offset)
                }
            default:
                next = []
            }
            messages.append(contentsOf: next)
            hasMoreMessages = next.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
            hasMoreMessages = false
        }
    }

    struct MessageThread: Identifiable {
        let id: String
        let subject: String
        let messages: [Message]
        var representative: Message? { messages.first }
        var count: Int { messages.count }
    }

    /// Groups the loaded messages into threads by normalized subject.
    var threads: [MessageThread] {
        var grouped: [String: [Message]] = [:]
        var order: [String] = []
        for message in messages {
            let key = MainModel.normalizedSubject(message.subject)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(message)
        }
        return order.map { key in
            let msgs = grouped[key] ?? []
            return MessageThread(id: key, subject: msgs.first?.subject ?? "(no subject)", messages: msgs)
        }
    }

    static func normalizedSubject(_ subject: String?) -> String {
        var text = (subject ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let prefixes = ["re:", "fwd:", "fw:", "aw:", "antw:"]
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes where text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return text.isEmpty ? "(no subject)" : text
    }

    /// "Account · Folder" label for a message, used in global search results.
    func contextLabel(for message: Message) -> String {
        let accountNode = accountNodes.first { $0.account.id == message.accountId }
        let folderName = accountNode?.folders.first { $0.id == message.folderId }?.name
        return [accountNode?.account.displayName, folderName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var selectedMessage: Message? {
        messages.first { $0.id == selectedMessageId }
    }

    func selectedFolderName() -> String? {
        for node in accountNodes {
            if let folder = node.folders.first(where: { $0.id == selectedFolderId }) {
                return folder.name
            }
        }
        return nil
    }

    func currentAccount() -> Account? {
        accountNodes.first { node in
            node.folders.contains { $0.id == selectedFolderId }
        }?.account
    }

    func currentFolderMessages() -> [Message] {
        guard let folderId = selectedFolderId else { return [] }
        return (try? app.repository.messages(folderId: folderId, limit: 1_000_000)) ?? []
    }

    func messages(for account: Account) -> [Message] {
        let folders = (try? app.repository.folders(accountId: account.id)) ?? []
        return folders.flatMap { folder -> [Message] in
            guard let id = folder.id else { return [] }
            return (try? app.repository.messages(folderId: id, limit: 1_000_000)) ?? []
        }
    }

    func loadContent(for message: Message) -> MessageContent? {
        guard let data = try? app.archiveStore.readEML(relativePath: message.emlPath) else { return nil }
        let mime = MIMEMessage(data: data)
        return MessageContent(html: mime.htmlBody, plainText: mime.plainText, attachments: mime.attachments)
    }
}
