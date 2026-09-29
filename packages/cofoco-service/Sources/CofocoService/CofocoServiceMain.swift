import Foundation
import Darwin
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOHTTP1

private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let router: ServiceRouter
    private var head: HTTPRequestHead?
    private var body: ByteBuffer?
    private var tooLarge = false

    init(router: ServiceRouter) { self.router = router }

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
            nonisolated(unsafe) let ctx = context
            Task {
                let response = exceeded ? Wire.error("invalid_input", status: 413) : await router.handle(request, uri: head.uri)
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
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--database" {
            database = URL(fileURLWithPath: CommandLine.arguments[2])
        } else if CommandLine.arguments.count == 1 {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cofoco", isDirectory: true)
            database = support.appendingPathComponent("cofoco.sqlite3")
        } else {
            fputs("usage: cofoco-service [--database PATH]\n", stderr)
            exit(64)
        }
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        let router = try ServiceRouter(database: database)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 128)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(router: router))
                }
            }
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: Wire.port).get()
        print("cofoco-service listening on 127.0.0.1:\(Wire.port)")
        try await channel.closeFuture.get()
        try await group.shutdownGracefully()
    }
}
