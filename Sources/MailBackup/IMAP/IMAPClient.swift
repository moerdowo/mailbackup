import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import NIOIMAP

/// A minimal async IMAP client built on swift-nio-imap. Commands are issued one
/// at a time; each `send` awaits the matching tagged completion. Not safe for
/// concurrent use from multiple tasks on the same instance.
final class IMAPClient {
    private let group: EventLoopGroup
    private var channel: Channel?
    private let router = IMAPResponseRouter()
    private var tagCounter = 0

    init(group: EventLoopGroup = MultiThreadedEventLoopGroup.singleton) {
        self.group = group
    }

    // MARK: - Connection

    func connect(host: String, port: Int, security: ConnectionSecurity, timeout: TimeAmount = .seconds(30)) async throws {
        let greetingPromise = group.next().makePromise(of: Void.self)
        let router = self.router

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(timeout)
            .channelInitializer { channel in
                do {
                    var handlers: [ChannelHandler] = []
                    if security == .ssl {
                        let context = try NIOSSLContext(configuration: .makeClientConfiguration())
                        handlers.append(try NIOSSLClientHandler(context: context, serverHostname: host))
                    }
                    handlers.append(IMAPClientHandler())
                    handlers.append(router)
                    router.installGreetingPromise(greetingPromise)
                    return channel.pipeline.addHandlers(handlers)
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }

        do {
            channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            throw IMAPError.connectionFailed(error.localizedDescription)
        }

        try await greetingPromise.futureResult.get()

        if security == .startTLS {
            try await startTLS(host: host)
        }
    }

    private func startTLS(host: String) async throws {
        let outcome = try await send(.startTLS)
        guard outcome.isOK else { throw IMAPError.commandFailed("STARTTLS failed: \(outcome.text)") }
        guard let channel else { throw IMAPError.notConnected }
        let context = try NIOSSLContext(configuration: .makeClientConfiguration())
        let tlsHandler = try NIOSSLClientHandler(context: context, serverHostname: host)
        try await channel.pipeline.addHandler(tlsHandler, position: .first).get()
    }

    func disconnect() async {
        guard let channel else { return }
        _ = try? await send(.logout)
        try? await channel.close().get()
        self.channel = nil
    }

    // MARK: - Commands

    func login(username: String, password: String) async throws {
        let outcome = try await send(.login(username: username, password: password))
        guard outcome.isOK else { throw IMAPError.authenticationFailed(outcome.text) }
    }

    func listMailboxes() async throws -> [MailboxEntry] {
        let reference = MailboxName(ByteBuffer(string: ""))
        let pattern = MailboxPatterns.mailbox(ByteBuffer(string: "*"))
        let outcome = try await send(.list(nil, reference: reference, pattern, []))
        guard outcome.isOK else { throw IMAPError.commandFailed(outcome.text) }

        var entries: [MailboxEntry] = []
        for payload in outcome.untagged {
            guard case .mailboxData(.list(let info)) = payload else { continue }
            let name = String(decoding: info.path.name.bytes, as: UTF8.self)
            let selectable = !info.attributes.contains(.noSelect) && !info.attributes.contains(.nonExistent)
            entries.append(MailboxEntry(name: name, selectable: selectable))
        }
        return entries
    }

    func select(mailbox name: String) async throws -> SelectResult {
        let mailbox = MailboxName(ByteBuffer(string: name))
        let outcome = try await send(.select(mailbox, []))
        guard outcome.isOK else { throw IMAPError.commandFailed(outcome.text) }

        var exists = 0
        var uidValidity: Int?
        var uidNext: Int?
        for payload in outcome.untagged {
            switch payload {
            case .mailboxData(.exists(let count)):
                exists = count
            case .conditionalState(.ok(let text)):
                switch text.code {
                case .uidValidity(let value): uidValidity = Int(value)
                case .uidNext(let value): uidNext = Int(value.rawValue)
                default: break
                }
            default:
                break
            }
        }
        return SelectResult(exists: exists, uidValidity: uidValidity, uidNext: uidNext)
    }

    /// Returns all UIDs in the currently selected mailbox.
    func searchAllUIDs() async throws -> [Int] {
        let outcome = try await send(.uidSearch(key: .all))
        guard outcome.isOK else { throw IMAPError.commandFailed(outcome.text) }
        var uids: [Int] = []
        for payload in outcome.untagged {
            if case .mailboxData(.search(let identifiers, _)) = payload {
                uids.append(contentsOf: identifiers.map { Int($0.rawValue) })
            }
        }
        return uids
    }

    /// Fetches one message by UID, including its full RFC822 bytes (BODY.PEEK[],
    /// so the \Seen flag is not set on the server).
    func fetchMessage(uid: Int) async throws -> FetchedMessage {
        guard let uidValue = UID(exactly: uid) else {
            throw IMAPError.commandFailed("Invalid UID \(uid)")
        }
        guard let set = MessageIdentifierSetNonEmpty(set: MessageIdentifierSet<UID>(uidValue)) else {
            throw IMAPError.commandFailed("Empty UID set")
        }
        let attributes: [FetchAttribute] = [
            .uid, .flags, .internalDate, .rfc822Size, .envelope,
            .bodySection(peek: true, .complete, nil),
        ]
        let outcome = try await send(.uidFetch(.set(set), attributes, []))
        guard outcome.isOK else { throw IMAPError.commandFailed(outcome.text) }
        return assembleMessage(uid: uid, from: outcome.fetchResponses)
    }

    // MARK: - Send

    private func nextTag() -> String {
        tagCounter += 1
        return "A\(String(format: "%04d", tagCounter))"
    }

    private func send(_ command: Command) async throws -> CommandOutcome {
        guard let channel else { throw IMAPError.notConnected }
        let tag = nextTag()
        let promise = channel.eventLoop.makePromise(of: CommandOutcome.self)
        let message = IMAPClientHandler.Message.part(.tagged(TaggedCommand(tag: tag, command: command)))
        let router = self.router
        channel.eventLoop.execute {
            router.addPending(IMAPResponseRouter.Pending(tag: tag, promise: promise))
            channel.writeAndFlush(message, promise: nil)
        }
        return try await promise.futureResult.get()
    }

    // MARK: - Response assembly

    private func assembleMessage(uid: Int, from responses: [FetchResponse]) -> FetchedMessage {
        var body = ByteBuffer()
        var flags: [String] = []
        var internalDate: Date?
        var size: Int?
        var subject: String?
        var fromName: String?
        var fromAddress: String?
        var toAddresses: String?
        var ccAddresses: String?
        var sentDate: Date?
        var messageID: String?
        var resolvedUID = uid
        var streaming = false

        for response in responses {
            switch response {
            case .startUID(let value):
                resolvedUID = Int(value.rawValue)
            case .start:
                break
            case .simpleAttribute(let attribute):
                switch attribute {
                case .uid(let value):
                    resolvedUID = Int(value.rawValue)
                case .flags(let values):
                    flags = values.map { String(reflecting: $0) }
                case .rfc822Size(let value):
                    size = value
                case .internalDate(let value):
                    internalDate = Self.date(from: value)
                case .envelope(let envelope):
                    subject = envelope.subject.map { Self.string(from: $0) }
                    if let first = envelope.from.first, let parsed = Self.address(from: first) {
                        fromName = parsed.name
                        fromAddress = parsed.address
                    }
                    toAddresses = Self.addressList(envelope.to)
                    ccAddresses = Self.addressList(envelope.cc)
                    if let date = envelope.date { sentDate = Self.parseRFC2822Date(String(date)) }
                    if let id = envelope.messageID { messageID = String(id) }
                default:
                    break
                }
            case .streamingBegin:
                streaming = true
            case .streamingBytes(var buffer):
                if streaming { body.writeBuffer(&buffer) }
            case .streamingEnd:
                streaming = false
            case .finish:
                break
            }
        }

        return FetchedMessage(
            uid: resolvedUID,
            flags: flags,
            internalDate: internalDate,
            size: size,
            rawData: Data(body.readableBytesView),
            subject: subject,
            fromName: fromName,
            fromAddress: fromAddress,
            toAddresses: toAddresses,
            ccAddresses: ccAddresses,
            sentDate: sentDate,
            messageID: messageID
        )
    }

    private static func string(from buffer: ByteBuffer) -> String {
        String(buffer: buffer)
    }

    private static func address(from element: EmailAddressListElement) -> (name: String?, address: String?)? {
        guard case .singleAddress(let address) = element else { return nil }
        let name = address.personName.map { string(from: $0) }
        let mailbox = address.mailbox.map { string(from: $0) }
        let host = address.host.map { string(from: $0) }
        let email: String?
        if let mailbox, let host {
            email = "\(mailbox)@\(host)"
        } else {
            email = mailbox ?? host
        }
        return (name, email)
    }

    private static func addressList(_ elements: [EmailAddressListElement]) -> String? {
        let parts: [String] = elements.compactMap { element in
            guard let parsed = address(from: element) else { return nil }
            switch (parsed.name, parsed.address) {
            case let (name?, addr?) where !name.isEmpty: return "\(name) <\(addr)>"
            case let (_, addr?): return addr
            case let (name?, nil): return name
            default: return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func date(from server: ServerMessageDate) -> Date? {
        let c = server.components
        var components = DateComponents()
        components.year = c.year
        components.month = c.month
        components.day = c.day
        components.hour = c.hour
        components.minute = c.minute
        components.second = c.second
        components.timeZone = TimeZone(secondsFromGMT: c.zoneMinutes * 60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)
    }

    private static let rfc2822Formatters: [DateFormatter] = {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z",
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    private static func parseRFC2822Date(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        for formatter in rfc2822Formatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}

/// Result of a single IMAP command: its final tagged state plus the untagged
/// and fetch responses received while it was in flight.
private struct CommandOutcome {
    let state: TaggedResponse.State
    let untagged: [ResponsePayload]
    let fetchResponses: [FetchResponse]

    var isOK: Bool {
        if case .ok = state { return true }
        return false
    }

    var text: String {
        switch state {
        case .ok(let t), .no(let t), .bad(let t): return t.text
        }
    }
}

/// Routes IMAP `Response`s to the in-flight command and captures the greeting.
/// All state is touched only on the channel's event loop.
private final class IMAPResponseRouter: ChannelInboundHandler {
    typealias InboundIn = Response

    struct Pending {
        let tag: String
        let promise: EventLoopPromise<CommandOutcome>
        var untagged: [ResponsePayload] = []
        var fetchResponses: [FetchResponse] = []
    }

    private var pending: [Pending] = []
    private var greetingPromise: EventLoopPromise<Void>?
    private var receivedGreeting = false

    func installGreetingPromise(_ promise: EventLoopPromise<Void>) {
        if receivedGreeting {
            promise.succeed(())
        } else {
            greetingPromise = promise
        }
    }

    func addPending(_ command: Pending) {
        pending.append(command)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = unwrapInboundIn(data)
        switch response {
        case .untagged(let payload):
            if !receivedGreeting {
                receivedGreeting = true
                greetingPromise?.succeed(())
                greetingPromise = nil
                return
            }
            if !pending.isEmpty { pending[0].untagged.append(payload) }
        case .fetch(let fetchResponse):
            if !pending.isEmpty { pending[0].fetchResponses.append(fetchResponse) }
        case .tagged(let tagged):
            guard !pending.isEmpty else { return }
            let command = pending.removeFirst()
            command.promise.succeed(
                CommandOutcome(
                    state: tagged.state,
                    untagged: command.untagged,
                    fetchResponses: command.fetchResponses
                )
            )
        case .fatal(let text):
            fail(IMAPError.fatal(text.text))
        case .authenticationChallenge, .idleStarted:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        fail(IMAPError.connectionFailed("Connection closed by server"))
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(error)
        context.close(promise: nil)
    }

    private func fail(_ error: Error) {
        greetingPromise?.fail(error)
        greetingPromise = nil
        let inflight = pending
        pending.removeAll()
        for command in inflight {
            command.promise.fail(error)
        }
    }
}
