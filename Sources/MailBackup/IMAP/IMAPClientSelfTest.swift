import Foundation

/// Development end-to-end test for the IMAP client. Run with real credentials:
///
///   MAILBACKUP_IMAP_HOST=imap.fastmail.com \
///   MAILBACKUP_IMAP_USER=you@example.com \
///   MAILBACKUP_IMAP_PASS=app-password \
///   ./MailBackup
///
/// Connects, logs in, lists mailboxes, selects INBOX, and fetches the newest
/// message, printing a summary, then exits.
enum IMAPClientSelfTest {
    static func runHeadlessIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["MAILBACKUP_IMAP_HOST"],
              let user = env["MAILBACKUP_IMAP_USER"],
              let pass = env["MAILBACKUP_IMAP_PASS"]
        else { return }
        let port = Int(env["MAILBACKUP_IMAP_PORT"] ?? "993") ?? 993
        let security = ConnectionSecurity(rawValue: env["MAILBACKUP_IMAP_SECURITY"] ?? "ssl") ?? .ssl

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let client = IMAPClient()
            do {
                try await client.connect(host: host, port: port, security: security)
                print("IMAP_CONNECT_OK")
                try await client.login(username: user, password: pass)
                print("IMAP_LOGIN_OK")
                let mailboxes = try await client.listMailboxes()
                print("IMAP_LIST_OK count=\(mailboxes.count) -> \(mailboxes.prefix(10).map(\.name))")
                let select = try await client.select(mailbox: "INBOX")
                print("IMAP_SELECT_OK exists=\(select.exists) uidValidity=\(select.uidValidity ?? -1) uidNext=\(select.uidNext ?? -1)")
                let uids = try await client.searchAllUIDs()
                print("IMAP_SEARCH_OK uids=\(uids.count)")
                if let newest = uids.max() {
                    let message = try await client.fetchMessage(uid: newest)
                    print("IMAP_FETCH_OK uid=\(message.uid) bytes=\(message.rawData.count) subject=\(message.subject ?? "<none>") from=\(message.fromAddress ?? "<none>")")

                    let headerUIDs = Array(uids.sorted().suffix(5))
                    let headers = try await client.fetchHeaders(uids: headerUIDs)
                    print("IMAP_HEADERS_OK requested=\(headerUIDs.count) got=\(headers.count) subjects=\(headers.prefix(3).map { $0.subject ?? "<none>" })")

                    let body = try await client.fetchBody(uid: newest)
                    print("IMAP_BODY_OK uid=\(newest) bytes=\(body.count)")
                }
                await client.disconnect()
                print("IMAP_OK")
                exit(0)
            } catch {
                print("IMAP_FAIL \(error.localizedDescription)")
                await client.disconnect()
                exit(1)
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
