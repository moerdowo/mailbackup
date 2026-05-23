import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import NIOIMAP

/// Minimal IMAP reachability probe: opens a TLS connection and reads the
/// server's initial greeting without authenticating. Proves the NIO + TLS +
/// IMAP parsing stack works end to end, and backs the onboarding
/// "Test connection" step.
enum IMAPProbe {
    struct ProbeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Connects over TLS to `host:port` and returns a description of the
    /// server's greeting response.
    static func greeting(host: String, port: Int = 993, timeout: TimeAmount = .seconds(10)) async throws -> String {
        let group = MultiThreadedEventLoopGroup.singleton
        let eventLoop = group.next()
        let promise = eventLoop.makePromise(of: String.self)

        let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(timeout)
            .channelInitializer { channel in
                do {
                    let ssl = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                    return channel.pipeline.addHandlers([
                        ssl,
                        IMAPClientHandler(),
                        GreetingHandler(promise: promise),
                    ])
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }

        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            promise.fail(error)
            throw error
        }

        let timeoutTask = eventLoop.scheduleTask(in: timeout) {
            promise.fail(ProbeError(message: "Timed out waiting for server greeting"))
            channel.close(promise: nil)
        }

        do {
            let result = try await promise.futureResult.get()
            timeoutTask.cancel()
            try? await channel.close().get()
            return result
        } catch {
            timeoutTask.cancel()
            try? await channel.close().get()
            throw error
        }
    }

    /// Headless smoke test entry point used during development:
    /// `MAILBACKUP_PROBE_HOST=imap.gmail.com ./MailBackup` prints the greeting
    /// and exits before the GUI launches.
    static func runHeadlessIfRequested() {
        guard let host = ProcessInfo.processInfo.environment["MAILBACKUP_PROBE_HOST"] else { return }
        let port = Int(ProcessInfo.processInfo.environment["MAILBACKUP_PROBE_PORT"] ?? "993") ?? 993
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let greeting = try await greeting(host: host, port: port)
                print("PROBE_OK \(greeting)")
            } catch {
                print("PROBE_FAIL \(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}

/// Captures the first IMAP `Response` (the server greeting) and fulfils a promise.
private final class GreetingHandler: ChannelInboundHandler {
    typealias InboundIn = Response

    private let promise: EventLoopPromise<String>
    private var fulfilled = false

    init(promise: EventLoopPromise<String>) {
        self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = unwrapInboundIn(data)
        guard !fulfilled else { return }
        fulfilled = true
        promise.succeed(String(describing: response))
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if !fulfilled {
            fulfilled = true
            promise.fail(error)
        }
        context.close(promise: nil)
    }
}
