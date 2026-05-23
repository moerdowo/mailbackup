import SwiftUI

@main
struct MailBackupApp: App {
    @State private var app = AppModel()
    @AppStorage(AppSettings.menuBarEnabledKey) private var menuBarEnabled = true

    init() {
        IMAPProbe.runHeadlessIfRequested()
        IMAPClientSelfTest.runHeadlessIfRequested()
        StorageSelfTest.runHeadlessIfRequested()
        MIMESelfTest.runHeadlessIfRequested()
        ExportSelfTest.runHeadlessIfRequested()
        ImportSelfTest.runHeadlessIfRequested()
        EncryptionSelfTest.runHeadlessIfRequested()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)

        MenuBarExtra(
            "MailBackup",
            systemImage: app.isSyncing ? "arrow.triangle.2.circlepath" : "tray.full",
            isInserted: $menuBarEnabled
        ) {
            MenuBarView()
                .environment(app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
