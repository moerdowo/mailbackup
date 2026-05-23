import SwiftUI

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
    let onAddAccount: () -> Void

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 220)
        } content: {
            messageList
                .frame(minWidth: 300)
        } detail: {
            MessageDetailView(model: model)
                .frame(minWidth: 420)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.syncAll() }
                } label: {
                    if model.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model.isSyncing)
                .help("Sync all accounts")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { onAddAccount() } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
        .navigationTitle("MailBackup")
        .navigationSubtitle(model.statusText ?? "")
    }

    private var sidebar: some View {
        List(selection: $model.selectedFolderId) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            }
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
                        .tag(folder.id)
                    }
                } header: {
                    Text(node.account.displayName)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.selectedFolderId) { _, _ in model.refreshMessages() }
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

private struct MessageRow: View {
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
