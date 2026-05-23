import SwiftUI

struct ContentView: View {
    @State private var host = "imap.gmail.com"
    @State private var port = "993"
    @State private var isTesting = false
    @State private var result: String?
    @State private var isError = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.full")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("MailBackup")
                .font(.largeTitle.bold())
            Text("Archive and back up your email locally over IMAP.")
                .foregroundStyle(.secondary)

            GroupBox("Connection test") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("IMAP host", text: $host)
                        TextField("Port", text: $port)
                            .frame(width: 70)
                    }
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(action: runTest) {
                            Text("Test connection")
                        }
                        .disabled(isTesting || host.isEmpty)
                        if isTesting { ProgressView().controlSize(.small) }
                    }

                    if let result {
                        Text(result)
                            .font(.callout.monospaced())
                            .foregroundStyle(isError ? .red : .green)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(6)
            }
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func runTest() {
        isTesting = true
        result = nil
        let host = host
        let port = Int(port) ?? 993
        Task {
            do {
                let greeting = try await IMAPProbe.greeting(host: host, port: port)
                await MainActor.run {
                    result = greeting
                    isError = false
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    result = error.localizedDescription
                    isError = true
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
