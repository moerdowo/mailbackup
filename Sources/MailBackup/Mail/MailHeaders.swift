import Foundation

/// Helpers for parsing header values and splitting mbox files (used by import,
/// which doesn't get IMAP envelopes).
enum MailHeaders {
    /// Parses the first address from a header like `Name <a@b.com>` or `a@b.com`.
    static func address(from headerValue: String) -> (name: String?, address: String?) {
        let value = RFC2047.decode(headerValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !value.isEmpty else { return (nil, nil) }
        if let lt = value.firstIndex(of: "<"), let gt = value.firstIndex(of: ">"), lt < gt {
            let addr = value[value.index(after: lt)..<gt].trimmingCharacters(in: .whitespaces)
            var name = String(value[..<lt]).trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? nil : name, addr.isEmpty ? nil : addr)
        }
        return (nil, value)
    }

    private static let dateFormatters: [DateFormatter] = {
        ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"].map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            return f
        }
    }()

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// Splits an mbox file into individual RFC822 messages. Boundaries are lines
    /// beginning with `From ` at column 0; the separator line itself is dropped.
    static func splitMbox(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        let n = bytes.count
        guard n > 0 else { return [] }

        let fromPrefix: [UInt8] = Array("From ".utf8)
        func isFromLine(at idx: Int) -> Bool {
            guard idx + fromPrefix.count <= n else { return false }
            for j in 0..<fromPrefix.count where bytes[idx + j] != fromPrefix[j] { return false }
            return true
        }

        var starts: [Int] = []
        if isFromLine(at: 0) { starts.append(0) }
        var i = 0
        while i < n {
            if bytes[i] == 10, isFromLine(at: i + 1) { starts.append(i + 1) }
            i += 1
        }
        guard !starts.isEmpty else { return [data] }  // not mbox-shaped: treat as one message

        var messages: [Data] = []
        for k in 0..<starts.count {
            var bodyStart = starts[k]
            while bodyStart < n, bytes[bodyStart] != 10 { bodyStart += 1 }
            if bodyStart < n { bodyStart += 1 }  // skip the "From " line
            let end = (k + 1 < starts.count) ? starts[k + 1] : n
            if bodyStart < end {
                messages.append(Data(bytes[bodyStart..<end]))
            }
        }
        return messages
    }
}
