import Foundation
import Darwin
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOHTTP1

private final class HTTPWorkTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var closing = false
    private var drained: CheckedContinuation<Void, Never>?

    func begin() -> Bool {
        lock.withLock {
            guard !closing else { return false }
            count += 1
            return true
        }
    }

    func finish() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            count -= 1
            guard closing && count == 0 else { return nil }
            let value = drained
            drained = nil
            return value
        }
        continuation?.resume()
    }

    func stopAndDrain() async {
        await withCheckedContinuation { continuation in
            let empty = lock.withLock {
                closing = true
                if count == 0 { return true }
                drained = continuation
                return false
            }
            if empty { continuation.resume() }
        }
    }
}

private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let router: ServiceRouter
    private let work: HTTPWorkTracker
    private var head: HTTPRequestHead?
    private var body: ByteBuffer?
    private var tooLarge = false

    init(router: ServiceRouter, work: HTTPWorkTracker) { self.router = router; self.work = work }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
            body = context.channel.allocator.buffer(capacity: 0)
            tooLarge = false
        case .body(var chunk):
            guard !tooLarge else { return }
            if (body?.readableBytes ?? 0) + chunk.readableBytes > 1_048_576 {
                tooLarge = true
                body = nil
            } else { body?.writeBuffer(&chunk) }
        case .end:
            guard let head else { return }
            let payload = body.flatMap { buffer in buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes).map { Data($0) } }
            let exceeded = tooLarge
            self.head = nil; body = nil; tooLarge = false
            let headers = Dictionary(head.headers.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
            let path = String(head.uri.split(separator: "?", maxSplits: 1).first ?? "")
            let request = HTTPRequest(method: head.method.rawValue, headers: headers, body: payload, path: path)
            let accepted = work.begin()
            nonisolated(unsafe) let ctx = context
            Task {
                defer { if accepted { work.finish() } }
                let response = !accepted ? Wire.error("unavailable", status: 503)
                    : exceeded ? Wire.error("invalid_input", status: 413) : await router.handle(request, uri: head.uri)
                let responseBody = response.bodyData
                ctx.eventLoop.execute {
                    var responseHead = HTTPResponseHead(version: head.version, status: HTTPResponseStatus(statusCode: response.statusCode))
                    for (name, value) in response.headers { responseHead.headers.add(name: name, value: value) }
                    responseHead.headers.replaceOrAdd(name: "Connection", value: "close")
                    if let responseBody { responseHead.headers.replaceOrAdd(name: "Content-Length", value: String(responseBody.count)) }
                    ctx.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
                    if let responseBody {
                        var buffer = ctx.channel.allocator.buffer(capacity: responseBody.count)
                        buffer.writeBytes(responseBody)
                        ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    }
                    ctx.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in ctx.close(promise: nil) }
                }
            }
        }
    }
}

@main struct CofocoServiceMain {
    static func main() async throws {
        let database: URL
        let parentPID: Int32?
        if [3, 5].contains(CommandLine.arguments.count), CommandLine.arguments[1] == "--database" {
            database = URL(fileURLWithPath: CommandLine.arguments[2])
            if CommandLine.arguments.count == 5 {
                guard CommandLine.arguments[3] == "--parent-pid", let value = Int32(CommandLine.arguments[4]),
                      value > 1, value == getppid() else {
                    fputs("cofoco-service: parent PID must match the actual spawning process (actual: \(getppid()))\n", stderr)
                    exit(64)
                }
                parentPID = value
            } else { parentPID = nil }
        } else if CommandLine.arguments.count == 1 {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cofoco", isDirectory: true)
            database = support.appendingPathComponent("cofoco.sqlite3")
            parentPID = nil
        } else {
            fputs("usage: cofoco-service [--database PATH [--parent-pid PID]]\n", stderr)
            exit(64)
        }
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        let router = try ServiceRouter(database: database)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let work = HTTPWorkTracker()
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 128)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(router: router, work: work))
                }
            }
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: Wire.port).get()
        let signals = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
            Darwin.signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { @Sendable in channel.close(promise: nil) }
            source.resume()
            return source
        }
        let parentMonitor = DispatchSource.makeTimerSource(queue: .global())
        if let parentPID {
            parentMonitor.schedule(deadline: .now() + 1, repeating: 1)
            parentMonitor.setEventHandler { @Sendable in
                if getppid() != parentPID { channel.close(promise: nil) }
            }
            parentMonitor.resume()
        } else { parentMonitor.resume() }
        print("cofoco-service listening on 127.0.0.1:\(Wire.port)")
        try await channel.closeFuture.get()
        await work.stopAndDrain()
        try await group.shutdownGracefully()
        signals.forEach { $0.cancel() }
        parentMonitor.cancel()
    }
}
