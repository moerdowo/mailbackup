import SwiftUI

@main
struct MailBackupApp: App {
    init() {
        IMAPProbe.runHeadlessIfRequested()
        IMAPClientSelfTest.runHeadlessIfRequested()
        StorageSelfTest.runHeadlessIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MailBackup") {}
            }
        }
    }
}
