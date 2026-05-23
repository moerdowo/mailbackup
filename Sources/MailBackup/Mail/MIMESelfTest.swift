import Foundation

/// Development smoke test for the MIME parser, run via
/// `MAILBACKUP_MIME_TEST=1 ./MailBackup`.
enum MIMESelfTest {
    static func runHeadlessIfRequested() {
        guard ProcessInfo.processInfo.environment["MAILBACKUP_MIME_TEST"] != nil else { return }

        let raw = """
        From: =?UTF-8?Q?Jos=C3=A9?= <jose@example.com>
        Subject: =?UTF-8?B?SGVsbG8gV29ybGQ=?=
        Content-Type: multipart/mixed; boundary="BOUND"

        --BOUND
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: quoted-printable

        Budget =E2=82=AC numbers attached.
        --BOUND
        Content-Type: application/pdf; name="report.pdf"
        Content-Disposition: attachment; filename="report.pdf"
        Content-Transfer-Encoding: base64

        JVBERi0xLjQK
        --BOUND--
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let message = MIMEMessage(data: Data(raw.utf8))
        let from = RFC2047.decode("=?UTF-8?Q?Jos=C3=A9?=")
        let subject = RFC2047.decode("=?UTF-8?B?SGVsbG8gV29ybGQ=?=")
        let plain = message.plainText ?? ""

        var failures: [String] = []
        if from != "José" { failures.append("from decode: \(from)") }
        if subject != "Hello World" { failures.append("subject decode: \(subject)") }
        if !plain.contains("Budget € numbers") { failures.append("plain text: \(plain)") }
        if !message.hasAttachments { failures.append("attachments not detected") }
        if message.attachments.first?.filename != "report.pdf" { failures.append("attachment name: \(String(describing: message.attachments.first?.filename))") }

        if failures.isEmpty {
            print("MIME_OK")
            exit(0)
        } else {
            print("MIME_FAIL " + failures.joined(separator: "; "))
            exit(1)
        }
    }
}
