import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(AppSettings.menuBarEnabledKey) private var menuBarEnabled = true
    @AppStorage(AppSettings.notificationsEnabledKey) private var notificationsEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Show MailBackup in the menu bar", isOn: $menuBarEnabled)
            } footer: {
                Text("The menu bar item shows sync status and lets you start or pause syncing without opening the main window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Notify when syncing finishes or fails", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, on in
                        if on { Notifier.requestAuthorization() }
                    }
            }
            Section {
                Toggle("Encrypt local archive (.eml files)", isOn: Binding(
                    get: { app.encryptionEnabled },
                    set: { app.setArchiveEncryption($0) }
                ))
                .disabled(app.isConvertingEncryption)
                if app.isConvertingEncryption {
                    HStack { ProgressView().controlSize(.small); Text("Converting archive…").font(.callout) }
                }
            } header: {
                Text("Security")
            } footer: {
                Text("Encrypts message files at rest with a key in your Keychain. The search index (subjects, senders, and body text) is not encrypted, so for full at-rest protection also keep FileVault on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Maintenance") {
                HStack {
                    Button {
                        app.runIntegrityCheck()
                    } label: {
                        Label("Verify Archive", systemImage: "checkmark.shield")
                    }
                    .disabled(app.isCheckingIntegrity)
                    if app.isCheckingIntegrity { ProgressView().controlSize(.small) }
                }
                if let result = app.integrityResult {
                    if result.missing == 0 {
                        Label("All \(result.total) messages present.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green).font(.callout)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("\(result.missing) of \(result.total) messages are missing their file.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).font(.callout)
                            Button(role: .destructive) { app.repairOrphans() } label: {
                                Text("Remove \(result.missing) Orphaned Entr\(result.missing == 1 ? "y" : "ies")")
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 460)
    }
}

enum AppSettings {
    static let menuBarEnabledKey = "menuBarEnabled"
    static let notificationsEnabledKey = "notificationsEnabled"
    static let encryptArchiveKey = "encryptArchive"
}
