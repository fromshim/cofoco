import Foundation
import XCTest
@testable import CofocoApp

private final class LostResponseProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var payloads: [Data] = []
    static func reset() { lock.withLock { requests = []; payloads = [] } }
    static var captured: [URLRequest] { lock.withLock { requests } }
    static var capturedPayloads: [Data] { lock.withLock { payloads } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let attempt = Self.lock.withLock {
            Self.requests.append(request); Self.payloads.append(body)
            return Self.requests.count
        }
        if attempt == 1 {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"schema_version\":1,\"outcome\":\"created\",\"todo_ids\":[\"same-id\"],\"revisions\":{\"same-id\":1}}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

final class AppAPITests: XCTestCase {
    @MainActor func testLostResponseReplaysSameBodyAndIdempotencyKey() async throws {
        LostResponseProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LostResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = AppAPI(session: session, ownerToken: { "fixture-secret" })
        let result: MutationResponse = try await api.request("POST", "/v1/owner/todos", body: [
            "idempotency_key": "one-click", "title": "One commitment", "scope": ["kind": "personal"], "reason": "fixture",
        ])
        XCTAssertEqual(result.todoIds, ["same-id"])
        let requests = LostResponseProtocol.captured
        XCTAssertEqual(requests.count, 2)
        let payloads = LostResponseProtocol.capturedPayloads
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0], payloads[1])
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: payloads[0]) as? [String: Any])
        XCTAssertEqual(payload["idempotency_key"] as? String, "one-click")
        XCTAssertEqual(requests[0].url, requests[1].url)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-secret")
    }
}
