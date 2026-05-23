import Foundation
import Observation

/// A persistent, newest-first activity log stored as JSON in Application Support.
@MainActor
@Observable
final class ActivityLog {
    private(set) var entries: [LogEntry] = []
    private let fileURL: URL
    private let maxEntries = 1000

    init() {
        let directory = (try? AppPaths.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory
        fileURL = directory.appendingPathComponent("activity-log.json")
        load()
    }

    func log(_ message: String, category: String = "General", level: LogEntry.Level = .info) {
        entries.insert(LogEntry(level: level, category: category, message: message), at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
