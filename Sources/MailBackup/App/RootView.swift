import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var isOnboarding: Bool?

    var body: some View {
        Group {
            switch isOnboarding {
            case .some(true):
                OnboardingView(onFinish: { isOnboarding = false })
            case .some(false):
                MainView(onAddAccount: { isOnboarding = true })
            case .none:
                Color.clear
            }
        }
        .onAppear {
            if isOnboarding == nil { isOnboarding = !app.hasAccounts }
        }
    }
}

/// Temporary placeholder until the full three-pane window is built.
struct MainView: View {
    @Environment(AppModel.self) private var app
    let onAddAccount: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("MailBackup").font(.largeTitle.bold())
            if let error = app.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            ForEach(app.accounts) { account in
                GroupBox(account.displayName) {
                    Text(account.email).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 420)
            }
            Button("Add Account") { onAddAccount() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
