import SwiftUI
import WebKit
import AppKit

struct MessageDetailView: View {
    @Bindable var model: MainModel
    @State private var content: MessageContent?
    @State private var showPlainText = false

    var body: some View {
        Group {
            if let message = model.selectedMessage {
                detail(for: message)
            } else {
                ContentUnavailableView("No message selected", systemImage: "envelope")
            }
        }
        .onChange(of: model.selectedMessageId) { _, _ in loadContent() }
        .onAppear { loadContent() }
    }

    private func loadContent() {
        content = model.selectedMessage.flatMap { model.loadContent(for: $0) }
        showPlainText = (content?.html == nil)
    }

    @ViewBuilder
    private func detail(for message: Message) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(for: message)
            Divider()
            bodyContent
            if let attachments = content?.attachments, !attachments.isEmpty {
                Divider()
                AttachmentBar(attachments: attachments)
            }
        }
    }

    private func header(for message: Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.subject?.isEmpty == false ? message.subject! : "(no subject)")
                .font(.title3.bold())
                .textSelection(.enabled)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let from = headerFrom(message) {
                        labeledRow("From", from)
                    }
                    if let to = message.toAddresses, !to.isEmpty {
                        labeledRow("To", to)
                    }
                    if let cc = message.ccAddresses, !cc.isEmpty {
                        labeledRow("Cc", cc)
                    }
                }
                Spacer()
                if let date = message.internalDate ?? message.date {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if content?.html != nil {
                Picker("", selection: $showPlainText) {
                    Text("Rich").tag(false)
                    Text("Plain").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let content {
            if !showPlainText, let html = content.html {
                HTMLBodyView(html: html)
            } else if let text = content.plainText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                ContentUnavailableView("No readable content", systemImage: "doc.plaintext")
            }
        } else {
            ContentUnavailableView("Could not read message", systemImage: "exclamationmark.triangle")
        }
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Text(value).font(.caption).textSelection(.enabled).lineLimit(2)
        }
    }

    private func headerFrom(_ message: Message) -> String? {
        switch (message.fromName, message.fromAddress) {
        case let (name?, addr?) where !name.isEmpty: return "\(name) <\(addr)>"
        case let (_, addr?): return addr
        case let (name?, nil): return name
        default: return nil
        }
    }
}

private struct AttachmentBar: View {
    let attachments: [MIMEMessage.Attachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    Button {
                        save(attachment)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(attachment.filename ?? "attachment").font(.caption).lineLimit(1)
                                Text(byteString(attachment.size)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .help("Save \(attachment.filename ?? "attachment")")
                }
            }
            .padding(12)
        }
    }

    private func save(_ attachment: MIMEMessage.Attachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.filename ?? "attachment"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? attachment.data.write(to: url)
        }
    }

    private func byteString(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

/// Renders an email HTML body in a WKWebView with all network loads blocked,
/// so remote tracking images and scripts never fetch.
private struct HTMLBodyView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        context.coordinator.webView = webView
        context.coordinator.load(html: html)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.load(html: html)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var webView: WKWebView?
        private var ruleListInstalled = false
        private var loadedHTML: String?

        func load(html: String) {
            guard let webView else { return }
            guard html != loadedHTML else { return }
            loadedHTML = html

            if ruleListInstalled {
                webView.loadHTMLString(html, baseURL: nil)
                return
            }
            let blockAll = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "mailbackup-block-all",
                encodedContentRuleList: blockAll
            ) { [weak self] list, _ in
                if let list { webView.configuration.userContentController.add(list) }
                self?.ruleListInstalled = true
                webView.loadHTMLString(html, baseURL: nil)
            }
        }
    }
}
