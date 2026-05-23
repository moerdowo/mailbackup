import SwiftUI

struct SettingsView: View {
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
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 220)
    }
}

enum AppSettings {
    static let menuBarEnabledKey = "menuBarEnabled"
    static let notificationsEnabledKey = "notificationsEnabled"
}
