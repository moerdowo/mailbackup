import Foundation

/// Connection presets to pre-fill the IMAP host/port/security for common providers.
struct MailProvider: Identifiable, Hashable {
    var name: String
    var host: String
    var port: Int
    var security: ConnectionSecurity
    var note: String?

    var id: String { name }

    static let presets: [MailProvider] = [
        MailProvider(name: "Gmail", host: "imap.gmail.com", port: 993, security: .ssl,
                     note: "Requires an app password (2-Step Verification)."),
        MailProvider(name: "iCloud", host: "imap.mail.me.com", port: 993, security: .ssl,
                     note: "Requires an app-specific password."),
        MailProvider(name: "Outlook", host: "outlook.office365.com", port: 993, security: .ssl, note: nil),
        MailProvider(name: "Fastmail", host: "imap.fastmail.com", port: 993, security: .ssl,
                     note: "Requires an app password."),
        MailProvider(name: "Yahoo", host: "imap.mail.yahoo.com", port: 993, security: .ssl,
                     note: "Requires an app password."),
        MailProvider(name: "Purelymail", host: "imap.purelymail.com", port: 993, security: .ssl,
                     note: "If Two-Factor Authentication is enabled, use an app password."),
        MailProvider(name: "Other", host: "", port: 993, security: .ssl,
                     note: "Enter your provider's IMAP server details manually."),
    ]
}

/// How often to sync automatically.
enum SyncInterval: String, CaseIterable, Identifiable {
    case manual
    case hourly
    case daily

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manually"
        case .hourly: return "Every hour"
        case .daily: return "Once a day"
        }
    }

    var minutes: Int? {
        switch self {
        case .manual: return nil
        case .hourly: return 60
        case .daily: return 1440
        }
    }

    init(minutes: Int?) {
        switch minutes {
        case .some(60): self = .hourly
        case .some(1440): self = .daily
        default: self = .manual
        }
    }
}
