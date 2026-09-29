import Foundation
import XCTest
@testable import CofocoCLI

final class ServiceClientTests: XCTestCase {
    func testCreateTodoUsesOwnerAPIAndDecodesSnakeCaseReceipt() async throws {
        let transport = StubTransport(responses: [
            "POST /v1/owner/todos": response(#"{"schema_version":1,"outcome":"created","todo_ids":["todo-1"],"revisions":{"todo-1":1},"proposal_id":null}"#),
        ])
        let client = try makeClient(transport: transport)

        let result = try await client.createTodo(title: "Write release note", scope: .personal,
                                                  reason: "Capture current work", idempotencyKey: "key-1")

        XCTAssertEqual(result.outcome, "created")
        XCTAssertEqual(result.todoIds, ["todo-1"])
        XCTAssertEqual(result.revisions["todo-1"], 1)
        XCTAssertNil(result.proposalId)
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-test")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Write release note")
        XCTAssertEqual(json["reason"] as? String, "Capture current work")
        XCTAssertEqual(json["idempotency_key"] as? String, "key-1")
        XCTAssertEqual((json["scope"] as? [String: String])?["kind"], "personal")
    }

    func testListBuildsScopeAndStatusQueryAndDecodesTodo() async throws {
        let transport = StubTransport(responses: [
            "GET /v1/owner/todos": response(#"{"schema_version":1,"todos":[{"id":"todo-2","title":"Review UI","scope":{"kind":"project","id":"cofoco"},"status":"in_progress","revision":7}]}"#),
        ])
        let client = try makeClient(transport: transport)

        let todos = try await client.listTodos(scope: "project:cofoco", query: "UI", status: .inProgress, limit: 12)

        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos[0].id, "todo-2")
        XCTAssertEqual(todos[0].scope, .project("cofoco"))
        XCTAssertEqual(todos[0].status, .inProgress)
        XCTAssertEqual(todos[0].revision, 7)
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") }), [
            "scope": "project:cofoco", "query": "UI", "status": "in_progress", "limit": "12",
        ])
    }

    func testCLIStatusReadsCurrentRevisionBeforePatch() async throws {
        let transport = StubTransport(responses: [
            "GET /v1/owner/todos/todo-1": response(#"{"schema_version":1,"todo":{"id":"todo-1","title":"Review UI","scope":{"kind":"personal"},"status":"open","revision":4,"steps":[],"notes":[]}}"#),
            "PATCH /v1/owner/todos/todo-1": response(#"{"schema_version":1,"outcome":"updated","todo_ids":["todo-1"],"revisions":{"todo-1":5},"proposal_id":null}"#),
        ])
        let client = try makeClient(transport: transport)
        let output = OutputCollector()
        let command = CofocoCommandLine(client: client, write: { output.append($0) }, writeError: { output.appendError($0) })

        let exitCode = await command.run(["status", "todo-1", "done", "--reason", "Owner completed it", "--key", "status-1"])

        XCTAssertEqual(exitCode, 0)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "PATCH"])
        let patch = try XCTUnwrap(requests.last)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(patch.httpBody)) as? [String: Any])
        XCTAssertEqual(json["expected_revision"] as? Int, 4)
        XCTAssertEqual(json["status"] as? String, "done")
        XCTAssertEqual(json["idempotency_key"] as? String, "status-1")
        XCTAssertEqual(output.values.count, 1)
        XCTAssertTrue(output.values[0].contains("updated: todo-1"))
        XCTAssertTrue(output.errors.isEmpty)
    }

    func testCLIShowReadsAndPrintsTodoDetails() async throws {
        let transport = StubTransport(responses: [
            "GET /v1/owner/todos/todo-1": response(#"{"schema_version":1,"todo":{"id":"todo-1","title":"Review UI","scope":{"kind":"project","id":"cofoco"},"status":"in_progress","revision":8,"steps":[{"id":"step-1","title":"Inspect rows","is_done":false}],"notes":[{"id":"note-1","text":"Keep the list compact."}]}}"#),
        ])
        let output = OutputCollector()
        let command = CofocoCommandLine(client: try makeClient(transport: transport),
                                        write: { output.append($0) }, writeError: { output.appendError($0) })

        let exitCode = await command.run(["show", "todo-1"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.values.contains("Review UI"))
        XCTAssertTrue(output.values.contains("Scope: Project cofoco"))
        XCTAssertTrue(output.values.contains("Revision: 8"))
        XCTAssertTrue(output.values.contains("  [ ] Inspect rows"))
        XCTAssertTrue(output.values.contains("  Keep the list compact."))
        XCTAssertTrue(output.errors.isEmpty)
    }

    func testIntegrationGrantNeverNeedsOrReturnsASecret() async throws {
        let transport = StubTransport(responses: [
            "POST /v1/owner/integrations": response(#"{"schema_version":1,"id":"claude-code","outcome":"created","mcp_url":"http://127.0.0.1:57321/mcp"}"#),
        ])
        let client = try makeClient(transport: transport)

        let result = try await client.grantIntegration(id: "claude-code", scopes: ["project:cofoco"],
                                                       idempotencyKey: "grant-1")

        XCTAssertEqual(result.id, "claude-code")
        XCTAssertEqual(result.mcpUrl, "http://127.0.0.1:57321/mcp")
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNil(json["bearer_token"])
        XCTAssertEqual(json["can_read"] as? Bool, true)
        XCTAssertEqual(json["can_write"] as? Bool, true)
        XCTAssertEqual(json["scopes"] as? [String], ["project:cofoco"])
    }

    func testAuthHeaderHelperPrintsOnlyDynamicHeaderJSON() async throws {
        let client = try makeClient(transport: StubTransport(responses: [:]))
        let output = OutputCollector()
        let command = CofocoCommandLine(client: client,
                                        integrationCredentials: FixedIntegrationCredentials(secret: "secret-value"),
                                        write: { output.append($0) }, writeError: { output.appendError($0) })

        let exitCode = await command.run(["integration", "auth-header", "claude-code"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.values, [#"{"Authorization":"Bearer claude-code.secret-value"}"#])
        XCTAssertTrue(output.errors.isEmpty)
    }

    func testClientRejectsNonLoopbackEndpoint() throws {
        XCTAssertThrowsError(try CofocoServiceClient(baseURL: URL(string: "http://example.com:57321")!,
                                                      tokenProvider: ClosureTokenProvider { "test" })) { error in
            XCTAssertEqual(error as? ServiceClientError, .invalidEndpoint)
        }
    }

    private func makeClient(transport: ServiceHTTPTransport) throws -> CofocoServiceClient {
        try CofocoServiceClient(tokenProvider: ClosureTokenProvider { "owner-test" }, transport: transport)
    }

    private func response(_ json: String, statusCode: Int = 200) -> ServiceHTTPResponse {
        ServiceHTTPResponse(statusCode: statusCode, data: Data(json.utf8))
    }
}

private actor StubTransport: ServiceHTTPTransport {
    private let responses: [String: ServiceHTTPResponse]
    private var captured: [URLRequest] = []

    init(responses: [String: ServiceHTTPResponse]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        captured.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        guard let response = responses[key] else { throw URLError(.resourceUnavailable) }
        return response
    }

    func requests() -> [URLRequest] { captured }
}

private final class OutputCollector {
    var values: [String] = []
    var errors: [String] = []
    func append(_ value: String) { values.append(value) }
    func appendError(_ value: String) { errors.append(value) }
}

private struct FixedIntegrationCredentials: IntegrationCredentialManaging {
    let secret: String
    func secret(for integrationID: String) throws -> String { secret }
    func removeSecret(for integrationID: String) throws {}
}
