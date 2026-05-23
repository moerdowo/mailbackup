import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.menuBarEnabledKey) private var menuBarEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Show MailBackup in the menu bar", isOn: $menuBarEnabled)
            } footer: {
                Text("The menu bar item shows sync status and lets you start or pause syncing without opening the main window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 180)
    }
}

enum AppSettings {
    static let menuBarEnabledKey = "menuBarEnabled"
}
