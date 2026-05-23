import SwiftUI

@main
struct MailBackupApp: App {
    @State private var app = AppModel()

    init() {
        IMAPProbe.runHeadlessIfRequested()
        IMAPClientSelfTest.runHeadlessIfRequested()
        StorageSelfTest.runHeadlessIfRequested()
        MIMESelfTest.runHeadlessIfRequested()
        ExportSelfTest.runHeadlessIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}
