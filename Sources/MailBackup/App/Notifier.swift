import Foundation
import UserNotifications

/// Thin wrapper around user notifications for sync completion/failure.
enum Notifier {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettings.notificationsEnabledKey) as? Bool ?? true
    }

    static func requestAuthorization() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
