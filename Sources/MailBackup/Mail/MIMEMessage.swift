import Foundation

/// A parsed MIME part. Bodies are decoded lazily by the accessors on
/// `MIMEMessage`.
final class MIMEPart {
    var headers: [String: String] = [:]   // lowercased header name -> raw value
    var contentType: String = "text/plain"
    var charset: String?
    var transferEncoding: String?
    var disposition: String?
    var filename: String?
    var boundary: String?
    var body: [UInt8] = []
    var subparts: [MIMEPart] = []

    var isMultipart: Bool { contentType.hasPrefix("multipart/") }
    var isAttachment: Bool {
        (disposition == "attachment") || (filename != nil && !contentType.hasPrefix("text/"))
    }
}

/// Best-effort RFC822/MIME parser. Good enough to extract searchable plaintext,
/// an HTML body for display, and attachment metadata. Not a full validator.
struct MIMEMessage {
    let root: MIMEPart

    init(data: Data) {
        root = MIMEMessage.parse(Array(data))
    }

    struct Attachment: Identifiable {
        let id = UUID()
        var filename: String?
        var mimeType: String
        var size: Int
        var data: Data
    }

    var plainText: String? {
        if let text = collectPlainText(root), !text.isEmpty { return text }
        if let html = firstHTML(root) { return MIMEMessage.stripHTML(html) }
        return nil
    }

    var htmlBody: String? {
        firstHTML(root)
    }

    var attachments: [Attachment] {
        var result: [Attachment] = []
        collectAttachments(root, into: &result)
        return result
    }

    var hasAttachments: Bool { !attachments.isEmpty }

    func snippet(maxLength: Int = 200) -> String? {
        guard let text = plainText else { return nil }
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > maxLength ? String(collapsed.prefix(maxLength)) + "…" : collapsed
    }

    // MARK: - Text collection

    private func collectPlainText(_ part: MIMEPart) -> String? {
        if part.isMultipart {
            if part.contentType == "multipart/alternative" {
                // Prefer the richest text alternative we can render: plain first.
                for sub in part.subparts where sub.contentType == "text/plain" && !sub.isAttachment {
                    if let text = collectPlainText(sub) { return text }
                }
                for sub in part.subparts where sub.contentType == "text/html" && !sub.isAttachment {
                    if let text = collectPlainText(sub) { return text }
                }
                return part.subparts.compactMap { collectPlainText($0) }.first
            }
            let texts = part.subparts.compactMap { collectPlainText($0) }
            return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
        }

        guard !part.isAttachment else { return nil }
        switch part.contentType {
        case "text/plain":
            return decodedText(part)
        case "text/html":
            return decodedText(part).map { MIMEMessage.stripHTML($0) }
        default:
            return nil
        }
    }

    private func firstHTML(_ part: MIMEPart) -> String? {
        if part.contentType == "text/html", !part.isAttachment {
            return decodedText(part)
        }
        for sub in part.subparts {
            if let html = firstHTML(sub) { return html }
        }
        return nil
    }

    private func collectAttachments(_ part: MIMEPart, into result: inout [Attachment]) {
        if part.isAttachment {
            let decoded = MIMEMessage.decodeBody(part)
            result.append(Attachment(
                filename: part.filename.map { RFC2047.decode($0) },
                mimeType: part.contentType,
                size: decoded.count,
                data: decoded
            ))
        }
        for sub in part.subparts {
            collectAttachments(sub, into: &result)
        }
    }

    private func decodedText(_ part: MIMEPart) -> String? {
        let decoded = MIMEMessage.decodeBody(part)
        let encoding = RFC2047.stringEncoding(for: part.charset ?? "utf-8")
        return String(data: decoded, encoding: encoding)
            ?? String(data: decoded, encoding: .utf8)
            ?? String(data: decoded, encoding: .isoLatin1)
    }

    // MARK: - Parsing

    private static func parse(_ bytes: [UInt8]) -> MIMEPart {
        let part = MIMEPart()
        let (headerBytes, bodyBytes) = splitHeadersAndBody(bytes)

        let headerText = String(decoding: headerBytes, as: UTF8.self)
        for (name, value) in parseHeaders(headerText) {
            part.headers[name.lowercased()] = value
        }

        if let contentType = part.headers["content-type"] {
            let (type, params) = parseParameterized(contentType)
            part.contentType = type.lowercased()
            part.charset = params["charset"]
            part.boundary = params["boundary"]
            if part.filename == nil { part.filename = params["name"] }
        }
        if let disposition = part.headers["content-disposition"] {
            let (value, params) = parseParameterized(disposition)
            part.disposition = value.lowercased()
            if let filename = params["filename"] { part.filename = filename }
        }
        part.transferEncoding = part.headers["content-transfer-encoding"]?
            .trimmingCharacters(in: .whitespaces).lowercased()

        if part.isMultipart, let boundary = part.boundary {
            for segment in splitByBoundary(bodyBytes, boundary: boundary) {
                part.subparts.append(parse(segment))
            }
        } else {
            part.body = bodyBytes
        }
        return part
    }

    private static func splitHeadersAndBody(_ bytes: [UInt8]) -> (header: [UInt8], body: [UInt8]) {
        // Look for CRLFCRLF, then LFLF as a fallback.
        if let range = firstRange(of: [13, 10, 13, 10], in: bytes) {
            return (Array(bytes[..<range.lowerBound]), Array(bytes[range.upperBound...]))
        }
        if let range = firstRange(of: [10, 10], in: bytes) {
            return (Array(bytes[..<range.lowerBound]), Array(bytes[range.upperBound...]))
        }
        return (bytes, [])
    }

    private static func parseHeaders(_ text: String) -> [(String, String)] {
        var headers: [(String, String)] = []
        var current: (name: String, value: String)?
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            if line.isEmpty { continue }
            if line.first == " " || line.first == "\t" {
                current?.value += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                if let done = current { headers.append((done.name, done.value)) }
                let name = String(line[..<colon])
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                current = (name, value)
            }
        }
        if let done = current { headers.append((done.name, done.value)) }
        return headers
    }

    /// Splits e.g. `text/plain; charset="utf-8"` into ("text/plain", ["charset": "utf-8"]).
    private static func parseParameterized(_ value: String) -> (value: String, params: [String: String]) {
        let segments = value.components(separatedBy: ";")
        let head = segments.first?.trimmingCharacters(in: .whitespaces) ?? ""
        var params: [String: String] = [:]
        for segment in segments.dropFirst() {
            guard let eq = segment.firstIndex(of: "=") else { continue }
            let key = segment[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var raw = segment[segment.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
                raw = String(raw.dropFirst().dropLast())
            }
            // Drop RFC 2231 ordering suffix like name*0.
            let baseKey = key.contains("*") ? String(key[..<key.firstIndex(of: "*")!]) : key
            params[baseKey, default: ""] += String(raw)
        }
        return (head, params)
    }

    private static func splitByBoundary(_ body: [UInt8], boundary: String) -> [[UInt8]] {
        let delimiter = Array("--\(boundary)".utf8)
        let positions = allRanges(of: delimiter, in: body).map { $0.lowerBound }
        guard positions.count >= 1 else { return [] }

        var segments: [[UInt8]] = []
        for index in 0..<positions.count {
            var start = positions[index] + delimiter.count
            // Closing delimiter "--boundary--": stop.
            if start + 1 < body.count, body[start] == UInt8(ascii: "-"), body[start + 1] == UInt8(ascii: "-") {
                break
            }
            // Skip to the end of the boundary line.
            while start < body.count, body[start] != 10 { start += 1 }
            if start < body.count { start += 1 } // past the LF

            let end = (index + 1 < positions.count) ? positions[index + 1] : body.count
            guard start <= end else { continue }
            var segmentEnd = end
            // Trim the CRLF that precedes the next boundary.
            if segmentEnd > start, body[segmentEnd - 1] == 10 { segmentEnd -= 1 }
            if segmentEnd > start, body[segmentEnd - 1] == 13 { segmentEnd -= 1 }
            if segmentEnd >= start {
                segments.append(Array(body[start..<segmentEnd]))
            }
        }
        return segments
    }

    // MARK: - Body decoding

    private static func decodeBody(_ part: MIMEPart) -> Data {
        switch part.transferEncoding {
        case "base64":
            let filtered = part.body.filter { $0 != 13 && $0 != 10 && $0 != 32 && $0 != 9 }
            return Data(base64Encoded: Data(filtered)) ?? Data(part.body)
        case "quoted-printable":
            return decodeQuotedPrintable(part.body)
        default:
            return Data(part.body)
        }
    }

    private static func decodeQuotedPrintable(_ bytes: [UInt8]) -> Data {
        var out = [UInt8]()
        var i = 0
        while i < bytes.count {
            let c = bytes[i]
            if c == UInt8(ascii: "=") {
                if i + 1 < bytes.count, bytes[i + 1] == 13, i + 2 < bytes.count, bytes[i + 2] == 10 {
                    i += 3 // soft line break CRLF
                    continue
                }
                if i + 1 < bytes.count, bytes[i + 1] == 10 {
                    i += 2 // soft line break LF
                    continue
                }
                if i + 2 < bytes.count,
                   let hi = RFC2047.hexValue(bytes[i + 1]), let lo = RFC2047.hexValue(bytes[i + 2]) {
                    out.append(hi << 4 | lo)
                    i += 3
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return Data(out)
    }

    // MARK: - HTML

    static func stripHTML(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "head"] {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>.*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Byte search

    private static func firstRange(of pattern: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
        allRanges(of: pattern, in: bytes, firstOnly: true).first
    }

    private static func allRanges(of pattern: [UInt8], in bytes: [UInt8], firstOnly: Bool = false) -> [Range<Int>] {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return [] }
        var ranges: [Range<Int>] = []
        var i = 0
        let limit = bytes.count - pattern.count
        while i <= limit {
            if bytes[i] == pattern[0] {
                var match = true
                for j in 1..<pattern.count where bytes[i + j] != pattern[j] {
                    match = false
                    break
                }
                if match {
                    ranges.append(i..<(i + pattern.count))
                    if firstOnly { return ranges }
                    i += pattern.count
                    continue
                }
            }
            i += 1
        }
        return ranges
    }
}
