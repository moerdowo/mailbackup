import Foundation

/// Resolves on-disk locations for the local archive.
enum AppPaths {
    static let appName = "MailBackup"

    /// `~/Library/Application Support/MailBackup`, created if needed.
    static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Default database location inside Application Support.
    static func defaultDatabaseURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("MailBackup.sqlite", isDirectory: false)
    }

    /// Default archive root (where `.eml` files live) inside Application Support.
    static func defaultArchiveRoot() throws -> URL {
        let dir = try applicationSupportDirectory().appendingPathComponent("Archives", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
