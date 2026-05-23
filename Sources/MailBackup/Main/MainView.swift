import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var model: MainModel?
    let onAddAccount: () -> Void

    var body: some View {
        Group {
            if let model {
                MainContent(model: model, onAddAccount: onAddAccount)
            } else {
                ProgressView()
            }
        }
        .onAppear { if model == nil { model = MainModel(app: app) } }
    }
}

private struct MainContent: View {
    @Bindable var model: MainModel
    @Environment(AppModel.self) private var app
    let onAddAccount: () -> Void

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 240)
        } detail: {
            rightArea
        }
        .onChange(of: app.dataRevision) { _, _ in model.reloadSidebar() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if app.isSyncing {
                    Button { app.cancelSync() } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .help("Stop syncing")
                } else {
                    Button { app.startSyncAllAccounts() } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Sync all accounts")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if app.isSyncing { ProgressView().controlSize(.small) }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export Selected Message…") { exportMessage() }
                        .disabled(model.selectedMessage == nil)
                    Button("Export Folder…") { exportFolder() }
                        .disabled(model.selectedFolderId == nil)
                    Button("Export Account…") { exportAccount() }
                        .disabled(model.currentAccount() == nil)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { onAddAccount() } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
        .navigationTitle("MailBackup")
        .navigationSubtitle(app.syncStatusText ?? model.exportStatus ?? "")
    }

    // MARK: - Export

    private func exportMessage() {
        guard let message = model.selectedMessage else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Exporter.filename(for: message)
        panel.allowedContentTypes = [UTType(filenameExtension: "eml") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Exporter.writeEML(message: message, store: model.app.archiveStore, to: url)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func exportFolder() {
        guard let folderName = model.selectedFolderName() else { return }
        let safe = sanitizeName(folderName)
        presentZipPanel(suggested: "\(safe).zip", folderName: safe, messages: model.currentFolderMessages())
    }

    private func exportAccount() {
        guard let account = model.currentAccount() else { return }
        let safe = sanitizeName(account.displayName)
        presentZipPanel(suggested: "\(safe).zip", folderName: safe, messages: model.messages(for: account))
    }

    private func presentZipPanel(suggested: String, folderName: String, messages: [Message]) {
        guard !messages.isEmpty else {
            model.errorMessage = "Nothing to export."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let store = model.app.archiveStore
        let count = messages.count
        model.exportStatus = "Exporting \(count) message\(count == 1 ? "" : "s")…"
        Task.detached {
            do {
                try Exporter.zip(messages: messages, store: store, folderName: folderName, to: url)
                await MainActor.run { model.exportStatus = nil }
            } catch {
                await MainActor.run {
                    model.errorMessage = error.localizedDescription
                    model.exportStatus = nil
                }
            }
        }
    }

    private func sanitizeName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "Export" : cleaned
    }

    @ViewBuilder
    private var rightArea: some View {
        switch model.selection {
        case .folder:
            HSplitView {
                messageList
                    .frame(minWidth: 280, idealWidth: 340, maxHeight: .infinity)
                MessageDetailView(model: model)
                    .frame(minWidth: 420, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        case .search:
            SearchView(model: model)
        case .jobs:
            JobsView()
        case .log:
            LogView()
        default:
            DashboardView(model: model, onAddAccount: onAddAccount)
        }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            if let error = model.errorMessage ?? app.syncError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            }
            Label("Dashboard", systemImage: "square.grid.2x2")
                .tag(SidebarItem.dashboard)
            Label("Search", systemImage: "magnifyingglass")
                .tag(SidebarItem.search)
            Label("Jobs", systemImage: "arrow.triangle.2.circlepath")
                .tag(SidebarItem.jobs)
            Label("Log", systemImage: "list.bullet.rectangle")
                .tag(SidebarItem.log)
            ForEach(model.accountNodes) { node in
                Section {
                    ForEach(node.folders) { folder in
                        HStack {
                            Label(folder.name, systemImage: "folder")
                            Spacer()
                            Text("\(folder.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.folder(folder.id))
                    }
                } header: {
                    Text(node.account.displayName)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.selection) { _, _ in
            model.searchText = ""   // start each view with a clean query
            model.refreshMessages()
        }
    }

    private var messageList: some View {
        List(model.messages, selection: $model.selectedMessageId) { message in
            MessageRow(message: message).tag(message.id)
        }
        .overlay {
            if model.messages.isEmpty {
                ContentUnavailableView(
                    model.searchText.isEmpty ? "No messages" : "No matches",
                    systemImage: model.searchText.isEmpty ? "tray" : "magnifyingglass"
                )
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search archived mail")
        .onChange(of: model.searchText) { _, _ in model.refreshMessages() }
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(senderDisplay)
                    .font(.subheadline.weight(isUnread ? .bold : .regular))
                    .lineLimit(1)
                Spacer()
                if message.hasAttachments {
                    Image(systemName: "paperclip").font(.caption2).foregroundStyle(.secondary)
                }
                Text(dateDisplay)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(message.subject?.isEmpty == false ? message.subject! : "(no subject)")
                .font(.callout.weight(isUnread ? .semibold : .regular))
                .lineLimit(1)
            if let snippet = message.snippet, !snippet.isEmpty {
                Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var isUnread: Bool {
        guard let flags = message.flags else { return true }
        return !flags.contains("Seen")
    }

    private var senderDisplay: String {
        if let name = message.fromName, !name.isEmpty { return name }
        return message.fromAddress ?? "Unknown sender"
    }

    private var dateDisplay: String {
        guard let date = message.internalDate ?? message.date else { return "" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
