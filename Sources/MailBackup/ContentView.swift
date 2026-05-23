import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.full")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("MailBackup")
                .font(.largeTitle.bold())
            Text("Archive and back up your email locally over IMAP.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
}
