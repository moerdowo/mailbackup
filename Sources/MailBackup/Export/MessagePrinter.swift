import AppKit

/// Renders a message to a paginated NSTextView for printing or PDF export.
enum MessagePrinter {
    private static let pageWidth: CGFloat = 540  // US Letter (612pt) minus margins

    static func exportPDF(message: Message, content: MessageContent, to url: URL) {
        let textView = makeTextView(message: message, content: content)
        let info = NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = url
        info.horizontalPagination = .fit
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    static func printMessage(message: Message, content: MessageContent) {
        let textView = makeTextView(message: message, content: content)
        let info = NSPrintInfo()
        info.horizontalPagination = .fit
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.run()
    }

    private static func makeTextView(message: Message, content: MessageContent) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 10))
        textView.textContainerInset = .zero
        textView.textContainer?.containerSize = NSSize(width: pageWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.textStorage?.setAttributedString(attributedString(message: message, content: content))

        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            textView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: ceil(used.height) + 8)
        }
        return textView
    }

    private static func attributedString(message: Message, content: MessageContent) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let subject = (message.subject?.isEmpty == false) ? message.subject! : "(no subject)"
        result.append(NSAttributedString(string: subject + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 16),
        ]))

        var meta = ""
        if let from = headerFrom(message) { meta += "From: \(from)\n" }
        if let to = message.toAddresses, !to.isEmpty { meta += "To: \(to)\n" }
        if let cc = message.ccAddresses, !cc.isEmpty { meta += "Cc: \(cc)\n" }
        if let date = message.internalDate ?? message.date {
            meta += "Date: \(date.formatted(date: .long, time: .shortened))\n"
        }
        result.append(NSAttributedString(string: meta + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))

        if let html = content.html,
           let data = html.data(using: .utf8),
           let body = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil) {
            result.append(body)
        } else {
            result.append(NSAttributedString(string: content.plainText ?? "", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
            ]))
        }
        return result
    }

    private static func headerFrom(_ message: Message) -> String? {
        switch (message.fromName, message.fromAddress) {
        case let (name?, addr?) where !name.isEmpty: return "\(name) <\(addr)>"
        case let (_, addr?): return addr
        case let (name?, nil): return name
        default: return nil
        }
    }
}
