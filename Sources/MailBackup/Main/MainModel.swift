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
    private var isLoadingPage = false
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

    /// Loads the first page for the current selection/query, resetting paging.
    func refreshMessages() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch selection {
            case .search:
                messages = trimmed.isEmpty ? [] : try app.repository.searchMessages(query: trimmed, filter: filter, limit: pageSize, offset: 0)
                searchTotal = trimmed.isEmpty ? 0 : (try? app.repository.searchMessageCount(query: trimmed, filter: filter)) ?? messages.count
            case .folder(let id):
                if trimmed.isEmpty {
                    messages = try app.repository.messages(folderId: id, filter: filter, limit: pageSize, offset: 0)
                    searchTotal = 0
                } else {
                    messages = try app.repository.searchMessages(query: trimmed, folderId: id, filter: filter, limit: pageSize, offset: 0)
                    searchTotal = (try? app.repository.searchMessageCount(query: trimmed, folderId: id, filter: filter)) ?? messages.count
                }
            default:
                messages = []
                searchTotal = 0
            }
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
            case .search:
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
