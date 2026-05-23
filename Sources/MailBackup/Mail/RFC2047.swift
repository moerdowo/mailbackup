import Foundation

/// Decodes RFC 2047 "encoded-words" found in email headers, e.g.
/// `=?UTF-8?Q?Hi=20there?=` or `=?UTF-8?B?SGk=?=`.
enum RFC2047 {
    private static let regex = try! NSRegularExpression(
        pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=",
        options: []
    )

    static func decode(_ input: String) -> String {
        guard input.contains("=?") else { return input }

        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }

        var result = ""
        var lastEnd = 0
        var previousWasEncoded = false

        for match in matches {
            let gap = ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            if !(previousWasEncoded && gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                result += gap
            }

            let charset = ns.substring(with: match.range(at: 1))
            let encoding = ns.substring(with: match.range(at: 2)).uppercased()
            let text = ns.substring(with: match.range(at: 3))
            result += decodeWord(charset: charset, encoding: encoding, text: text) ?? ns.substring(with: match.range)

            lastEnd = match.range.location + match.range.length
            previousWasEncoded = true
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    private static func decodeWord(charset: String, encoding: String, text: String) -> String? {
        let bytes: Data?
        switch encoding {
        case "B":
            bytes = Data(base64Encoded: text)
        case "Q":
            bytes = decodeQ(text)
        default:
            return nil
        }
        guard let bytes else { return nil }
        let enc = stringEncoding(for: charset)
        return String(data: bytes, encoding: enc) ?? String(data: bytes, encoding: .isoLatin1)
    }

    private static func decodeQ(_ text: String) -> Data? {
        var bytes = [UInt8]()
        let chars = Array(text.utf8)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == UInt8(ascii: "_") {
                bytes.append(UInt8(ascii: " "))
                i += 1
            } else if c == UInt8(ascii: "="), i + 2 < chars.count,
                      let hi = hexValue(chars[i + 1]), let lo = hexValue(chars[i + 2]) {
                bytes.append(hi << 4 | lo)
                i += 3
            } else {
                bytes.append(c)
                i += 1
            }
        }
        return Data(bytes)
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        default: return nil
        }
    }

    static func stringEncoding(for charset: String) -> String.Encoding {
        switch charset.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "us-ascii", "ascii": return .ascii
        case "iso-8859-1", "latin1", "latin-1": return .isoLatin1
        case "iso-8859-2": return .isoLatin2
        case "windows-1252", "cp1252": return .windowsCP1252
        case "windows-1251", "cp1251": return .windowsCP1251
        case "utf-16": return .utf16
        default: return .utf8
        }
    }
}
