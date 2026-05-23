import Foundation

/// One line in the persistent activity log.
struct LogEntry: Identifiable, Codable, Equatable {
    enum Level: String, Codable {
        case info, warning, error
    }

    var id: UUID
    var date: Date
    var level: Level
    var category: String
    var message: String

    init(id: UUID = UUID(), date: Date = Date(), level: Level = .info, category: String, message: String) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }
}
