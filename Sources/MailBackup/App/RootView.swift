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
