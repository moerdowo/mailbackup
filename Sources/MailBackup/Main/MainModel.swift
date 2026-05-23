import Foundation
import Observation

struct MessageContent {
    var html: String?
    var plainText: String?
    var attachments: [MIMEMessage.Attachment]
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
        var id: String { account.id }
    }

    var accountNodes: [AccountNode] = []
    var selectedFolderId: Int64?
    var messages: [Message] = []
    var selectedMessageId: Int64?
    var searchText = ""

    var isSyncing = false
    var statusText: String?
    var errorMessage: String?

    init(app: AppModel) {
        self.app = app
        reloadSidebar()
    }

    func reloadSidebar() {
        var nodes: [AccountNode] = []
        for account in app.accounts {
            let folders = (try? app.repository.folders(accountId: account.id)) ?? []
            let folderNodes = folders.compactMap { folder -> FolderNode? in
                guard let id = folder.id else { return nil }
                let count = (try? app.repository.messageCount(folderId: id)) ?? 0
                return FolderNode(folder: folder, count: count)
            }
            let total = (try? app.repository.messageCount(accountId: account.id)) ?? 0
            nodes.append(AccountNode(account: account, folders: folderNodes, total: total))
        }
        accountNodes = nodes
        if selectedFolderId == nil {
            selectedFolderId = nodes.first?.folders.first?.id
        }
        refreshMessages()
    }

    func refreshMessages() {
        guard let folderId = selectedFolderId else {
            messages = []
            return
        }
        do {
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                messages = try app.repository.messages(folderId: folderId)
            } else {
                messages = try app.repository.searchMessages(query: trimmed, folderId: folderId)
            }
            if !messages.contains(where: { $0.id == selectedMessageId }) {
                selectedMessageId = messages.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
            messages = []
        }
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

    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        for account in app.accounts {
            guard let password = app.password(for: account) else {
                errorMessage = "No saved password for \(account.email)."
                continue
            }
            let folderNames = ((try? app.repository.folders(accountId: account.id)) ?? []).map(\.name)
            guard !folderNames.isEmpty else { continue }
            do {
                try await app.syncEngine.sync(account: account, password: password, folderNames: folderNames) { progress in
                    Task { @MainActor in
                        self.statusText = "\(account.email): \(progress.phase) \(progress.messagesTotal > 0 ? "(\(progress.messagesDone)/\(progress.messagesTotal))" : "")"
                    }
                }
            } catch {
                errorMessage = "Sync failed for \(account.email): \(error.localizedDescription)"
            }
        }
        statusText = nil
        reloadSidebar()
    }
}
