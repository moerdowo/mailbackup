import AppKit
import Quartz

/// Drives the shared Quick Look panel for files and attachment data.
final class QuickLookController: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookController()
    private var items: [NSURL] = []

    func preview(urls: [URL]) {
        items = urls.map { $0 as NSURL }
        guard !items.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        items[index]
    }
}

enum QuickLook {
    private static let tempDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MailBackupQuickLook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func preview(fileURL: URL) {
        QuickLookController.shared.preview(urls: [fileURL])
    }

    /// Writes data to a temp file (so Quick Look can read it) and previews it.
    static func preview(data: Data, filename: String) {
        let name = filename.isEmpty ? "attachment" : filename
        let url = tempDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        QuickLookController.shared.preview(urls: [url])
    }
}
