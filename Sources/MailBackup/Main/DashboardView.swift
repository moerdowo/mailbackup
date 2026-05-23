import SwiftUI

struct DashboardView: View {
    @Bindable var model: MainModel
    @Environment(AppModel.self) private var app
    let onAddAccount: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Dashboard")
                        .font(.largeTitle.bold())
                    Spacer()
                    Button {
                        model.searchText = ""
                        model.selection = .search
                    } label: {
                        Label("Search Archive", systemImage: "magnifyingglass")
                    }
                    .controlSize(.large)
                    .disabled(model.totalMessages == 0)
                    .help("Search across all accounts")
                }

                SyncStatusCard(model: model, onAddAccount: onAddAccount)

                statsGrid

                accountsSection
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            StatCard(title: "Accounts", value: "\(model.accountNodes.count)", systemImage: "person.crop.circle")
            StatCard(title: "Messages", value: "\(model.totalMessages)", systemImage: "envelope")
            StatCard(title: "Folders", value: "\(model.totalFolders)", systemImage: "folder")
            StatCard(title: "Storage", value: byteString(model.totalStorageBytes), systemImage: "internaldrive")
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Accounts").font(.title2.bold())
                Spacer()
                Button {
                    onAddAccount()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }

            if model.accountNodes.isEmpty {
                Text("No accounts yet.").foregroundStyle(.secondary)
            } else {
                ForEach(model.accountNodes) { node in
                    AccountCard(node: node, byteString: byteString)
                }
            }
        }
    }

    private func byteString(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

private struct SyncStatusCard: View {
    @Bindable var model: MainModel
    @Environment(AppModel.self) private var app
    let onAddAccount: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if app.isPaused {
                        Label("Syncing paused", systemImage: "pause.circle.fill")
                            .font(.headline).foregroundStyle(.orange)
                        Text("Automatic and manual syncs are paused.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if app.isSyncing {
                        Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        if let progress = app.syncProgress {
                            Text(app.syncStatusText ?? progress.phase)
                                .font(.callout).foregroundStyle(.secondary)
                                .lineLimit(1)
                            if progress.messagesTotal > 0 {
                                ProgressView(value: Double(progress.messagesDone), total: Double(progress.messagesTotal))
                                    .frame(maxWidth: 320)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                    } else if let error = app.syncError {
                        Label("Sync stopped", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(.red)
                        Text(error).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Label("Up to date", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                        Text("All accounts archived locally.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                controls
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if app.isPaused {
            Button { app.setPaused(false) } label: {
                Label("Resume", systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)
        } else {
            HStack(spacing: 8) {
                if app.isSyncing {
                    Button(role: .destructive) { app.cancelSync() } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                } else {
                    Button { app.startSyncAllAccounts() } label: {
                        Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.accountNodes.isEmpty)
                    .keyboardShortcut("r", modifiers: .command)
                }
                Button { app.setPaused(true) } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.title3.bold().monospacedDigit())
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
        }
    }
}

private struct AccountCard: View {
    @Environment(AppModel.self) private var app
    let node: MainModel.AccountNode
    let byteString: (Int) -> String
    @State private var confirmingDelete = false
    @State private var showingSettings = false

    private var isPaused: Bool { node.account.isPaused }

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(node.account.displayName).font(.headline)
                        if isPaused {
                            Text("Paused")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.orange.opacity(0.18), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(node.account.email).font(.callout).foregroundStyle(.secondary)
                    FlowLayout(spacing: 12, lineSpacing: 4) {
                        Label("\(node.total)", systemImage: "envelope")
                        Label("\(node.folders.count)", systemImage: "folder")
                        Label(byteString(node.storageBytes), systemImage: "internaldrive")
                        if let date = node.lastSyncedAt {
                            Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        } else {
                            Label("Never synced", systemImage: "clock")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    app.syncAccount(node.account)
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(app.isSyncing || app.isPaused || isPaused)
                .fixedSize()

                Menu {
                    Button { showingSettings = true } label: {
                        Label("Settings…", systemImage: "gearshape")
                    }
                    if isPaused {
                        Button { app.setAccountPaused(node.account, paused: false) } label: {
                            Label("Resume Syncing", systemImage: "play")
                        }
                    } else {
                        Button { app.setAccountPaused(node.account, paused: true) } label: {
                            Label("Pause Syncing", systemImage: "pause")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Remove Account…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(6)
        }
        .sheet(isPresented: $showingSettings) {
            AccountSettingsView(account: node.account)
                .environment(app)
        }
        .confirmationDialog(
            "Remove \(node.account.email)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Remove Account and Local Archive", role: .destructive) {
                app.deleteAccount(node.account)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the account's saved password and its \(node.total) archived message\(node.total == 1 ? "" : "s") from this Mac. Mail on the server is not affected.")
        }
    }
}
