import SwiftUI

struct DashboardView: View {
    @Bindable var model: MainModel
    @Environment(AppModel.self) private var app
    let onAddAccount: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Dashboard")
                    .font(.largeTitle.bold())

                SyncStatusCard(model: model, onAddAccount: onAddAccount)

                statsGrid

                accountsSection
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
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
                    if app.isSyncing {
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
            }
            .padding(6)
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

    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.account.displayName).font(.headline)
                    Text(node.account.email).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
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
                Spacer()
                Button {
                    app.syncAccount(node.account)
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(app.isSyncing)
            }
            .padding(6)
        }
    }
}
