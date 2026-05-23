import SwiftUI
import AppKit

/// The menu-bar dropdown: a compact mirror of the dashboard — sync status,
/// archive stats, per-account quick sync, and global controls.
struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    @State private var totalMessages = 0
    @State private var totalStorage = 0
    @State private var accountStats: [(account: Account, count: Int)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill").foregroundStyle(.tint)
                Text("MailBackup").font(.headline)
                Spacer()
            }

            statusRow
            if app.isSyncing, let progress = app.syncProgress, progress.messagesTotal > 0 {
                ProgressView(value: Double(progress.messagesDone), total: Double(progress.messagesTotal))
            }

            Divider()

            HStack(spacing: 18) {
                stat("\(app.accounts.count)", "Accounts")
                stat("\(totalMessages)", "Messages")
                stat(byteString(totalStorage), "Storage")
            }

            if !accountStats.isEmpty {
                Divider()
                VStack(spacing: 4) {
                    ForEach(accountStats, id: \.account.id) { entry in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.account.displayName).font(.callout).lineLimit(1)
                                Text("\(entry.count) message\(entry.count == 1 ? "" : "s")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.account.isLocal {
                                Text("Imported").font(.caption2).foregroundStyle(.blue)
                            } else if entry.account.isPaused {
                                Text("Paused").font(.caption2).foregroundStyle(.orange)
                            }
                            if !entry.account.isLocal {
                                Button {
                                    app.syncAccount(entry.account)
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.borderless)
                                .disabled(app.isSyncing || app.isPaused || entry.account.isPaused)
                            }
                        }
                    }
                }
            }

            Divider()
            controls

            Divider()
            HStack {
                Button("Open MailBackup") { openMainWindow() }
                Spacer()
                SettingsLink { Text("Settings…") }
            }
            Button("Quit MailBackup") { NSApplication.shared.terminate(nil) }
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear(perform: refreshStats)
        .onChange(of: app.dataRevision) { _, _ in refreshStats() }
    }

    @ViewBuilder
    private var statusRow: some View {
        if app.isPaused {
            Label("Syncing paused", systemImage: "pause.circle.fill").foregroundStyle(.orange)
        } else if app.isSyncing {
            Label(app.syncStatusText ?? "Syncing…", systemImage: "arrow.triangle.2.circlepath")
                .lineLimit(1)
        } else if let error = app.syncError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).lineLimit(2)
        } else {
            Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if app.isPaused {
                Button { app.setPaused(false) } label: {
                    Label("Resume", systemImage: "play.circle")
                }
            } else {
                if app.isSyncing {
                    Button { app.cancelSync() } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                } else {
                    Button { app.startSyncAllAccounts() } label: {
                        Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(app.accounts.isEmpty)
                }
                Button { app.setPaused(true) } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
            }
            Spacer()
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func refreshStats() {
        let accounts = app.accounts
        accountStats = accounts.map { account in
            (account, (try? app.repository.messageCount(accountId: account.id)) ?? 0)
        }
        totalMessages = accountStats.reduce(0) { $0 + $1.count }
        totalStorage = accounts.reduce(0) { $0 + ((try? app.repository.totalArchivedSize(accountId: $1.id)) ?? 0) }
    }

    private func byteString(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
