import Foundation
import XCTest
import MCP
@testable import CofocoService

final class ServiceRouterTests: XCTestCase {
    private func request(_ method: String, _ path: String, token: String? = nil, object: [String: Any]? = nil) -> HTTPRequest {
        var headers = ["Host": "127.0.0.1:57321", "Accept": "application/json", "Content-Type": "application/json"]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        let body = object.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return HTTPRequest(method: method, headers: headers, body: body, path: path)
    }

    private func json(_ response: ServiceHTTPResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(response.bodyData)) as? [String: Any])
    }

    func testOwnerAndIntegrationTodoRoundtripAndRetry() async throws {
        let database = FileManager.default.temporaryDirectory.appendingPathComponent("cofoco-service-\(UUID().uuidString).sqlite3")
        let vault = KeychainVault(testTokens: ["owner-local": "owner-secret", "integration:agent-a": "agent-secret"])
        let router = try ServiceRouter(database: database, vault: vault)

        let denied = await router.handle(request("GET", "/v1/owner/todos"), uri: "/v1/owner/todos")
        XCTAssertEqual(denied.statusCode, 401)
        let wrongHost = await router.handle(HTTPRequest(method: "GET", headers: ["Host": "evil.example"], path: "/health"), uri: "/health")
        XCTAssertEqual(wrongHost.statusCode, 403)

        let grantPath = "/v1/owner/integrations"
        let grant = await router.handle(request("POST", grantPath, token: "owner-secret", object: [
            "id": "agent-a", "scopes": ["personal"], "idempotency_key": "grant-agent-a",
        ]), uri: grantPath)
        XCTAssertEqual(grant.statusCode, 200)
        XCTAssertNil(try json(grant)["bearer_token"])

        let initialize: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"],
        ]]
        let initResponse = await router.handle(request("POST", "/mcp", token: "agent-a.agent-secret", object: initialize), uri: "/mcp")
        XCTAssertEqual(initResponse.statusCode, 200)

        func tool(_ id: Int, _ name: String, _ args: [String: Any]) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": name, "arguments": args]]
        }
        let create = tool(2, "cofoco_create_todo", ["title": "MCP 실제 Todo", "scope": "personal",
                                                    "explicitly_agreed": true, "reason": "owner asked", "idempotency_key": "create-once"])
        let created = await router.handle(request("POST", "/mcp", token: "agent-a.agent-secret", object: create), uri: "/mcp")
        XCTAssertEqual(created.statusCode, 200)
        let createdText = try XCTUnwrap(((json(created)["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String)
        let createdData = try XCTUnwrap(createdText.data(using: .utf8))
        let createdObject = try XCTUnwrap(JSONSerialization.jsonObject(with: createdData) as? [String: Any])
        XCTAssertEqual(createdObject["outcome"] as? String, "created")
        let todoID = try XCTUnwrap((createdObject["todo_ids"] as? [String])?.first)

        let retried = await router.handle(request("POST", "/mcp", token: "agent-a.agent-secret", object: create), uri: "/mcp")
        XCTAssertEqual(retried.statusCode, 200)
        let retryText = try XCTUnwrap(((json(retried)["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertEqual(retryText, createdText)

        // A second client may initialize with the same grant while the first is still active.
        // Both use JSON-RPC id 7; the handshake must not poison either response.
        var nextInitialize = initialize
        nextInitialize["id"] = 7
        let repeatedRequest = request("POST", "/mcp", token: "agent-a.agent-secret", object: nextInitialize)
        let oldClientRequest = request("POST", "/mcp", token: "agent-a.agent-secret",
                                       object: tool(7, "cofoco_get_todo", ["id": todoID]))
        async let repeated = router.handle(repeatedRequest, uri: "/mcp")
        async let oldClientRead = router.handle(oldClientRequest, uri: "/mcp")
        let repeatedResponse = await repeated, oldClientResponse = await oldClientRead
        XCTAssertEqual(repeatedResponse.statusCode, 200)
        XCTAssertNotNil(try json(repeatedResponse)["result"])
        XCTAssertNil(try json(repeatedResponse)["error"])
        let oldClientText = try XCTUnwrap(((json(oldClientResponse)["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(oldClientText.contains(todoID))

        let thirdInitialize = await router.handle(repeatedRequest, uri: "/mcp")
        XCTAssertEqual(thirdInitialize.statusCode, 200)
        XCTAssertNotNil(try json(thirdInitialize)["result"])
        XCTAssertNil(try json(thirdInitialize)["error"])

        let malformedInitialize = request("POST", "/mcp", token: "agent-a.agent-secret", object: [
            "jsonrpc": "2.0", "id": 8, "method": "initialize", "params": ["protocolVersion": 123],
        ])
        let failedHandshake = await router.handle(malformedInitialize, uri: "/mcp")
        let handshakeHasError = try json(failedHandshake)["error"] != nil
        XCTAssertTrue(failedHandshake.statusCode >= 400 || handshakeHasError)
        let stillWorking = await router.handle(oldClientRequest, uri: "/mcp")
        XCTAssertEqual(stillWorking.statusCode, 200)
        XCTAssertNotNil(try json(stillWorking)["result"])

        let update = tool(3, "cofoco_update_todo", ["id": todoID, "expected_revision": 1, "status": "in_progress",
                                                    "reason": "starting work", "idempotency_key": "start-once"])
        let updated = await router.handle(request("POST", "/mcp", token: "agent-a.agent-secret", object: update), uri: "/mcp")
        XCTAssertEqual(updated.statusCode, 200)

        let shown = await router.handle(request("GET", "/v1/owner/todos/\(todoID)", token: "owner-secret"), uri: "/v1/owner/todos/\(todoID)")
        XCTAssertEqual((try json(shown)["todo"] as? [String: Any])?["status"] as? String, "in_progress")
        let patchPath = "/v1/owner/todos/\(todoID)"
        let ownerStatus = await router.handle(request("PATCH", patchPath, token: "owner-secret", object: [
            "expected_revision": 2, "status": "done", "reason": "owner finished", "idempotency_key": "owner-done",
        ]), uri: patchPath)
        XCTAssertEqual(try json(ownerStatus)["outcome"] as? String, "updated")
        let completed = await router.handle(request("GET", patchPath, token: "owner-secret"), uri: patchPath)
        XCTAssertEqual((try json(completed)["todo"] as? [String: Any])?["status"] as? String, "done")

        let revokePath = "/v1/owner/integrations/agent-a"
        let revoked = await router.handle(request("DELETE", revokePath, token: "owner-secret", object: ["idempotency_key": "revoke-agent-a"]), uri: revokePath)
        XCTAssertEqual(revoked.statusCode, 200)
        let deniedRead = await router.handle(request("POST", "/mcp", token: "agent-a.agent-secret", object: tool(4, "cofoco_get_todo", ["id": todoID])), uri: "/mcp")
        XCTAssertEqual(deniedRead.statusCode, 401)
    }

    func testConcurrentSameRPCIDKeepsGrantScopesSeparate() async throws {
        let database = FileManager.default.temporaryDirectory.appendingPathComponent("cofoco-service-\(UUID().uuidString).sqlite3")
        let vault = KeychainVault(testTokens: ["owner-local": "owner-secret", "integration:personal-agent": "secret-a",
                                               "integration:project-agent": "secret-b"])
        let router = try ServiceRouter(database: database, vault: vault)
        let projectPath = "/v1/owner/projects"
        let projectResponse = await router.handle(request("POST", projectPath, token: "owner-secret", object: [
            "name": "Isolated Project", "idempotency_key": "create-project",
        ]), uri: projectPath)
        let projectID = try XCTUnwrap(json(projectResponse)["id"] as? String)

        for (id, scope) in [("personal-agent", "personal"), ("project-agent", "project:\(projectID)")] {
            let path = "/v1/owner/integrations"
            let response = await router.handle(request("POST", path, token: "owner-secret", object: [
                "id": id, "scopes": [scope], "idempotency_key": "grant-\(id)",
            ]), uri: path)
            XCTAssertEqual(response.statusCode, 200)
        }
        for (title, scope, key) in [("Private personal", ["kind": "personal"], "personal-todo"),
                                    ("Private project", ["kind": "project", "id": projectID], "project-todo")] {
            let path = "/v1/owner/todos"
            let response = await router.handle(request("POST", path, token: "owner-secret", object: [
                "title": title, "scope": scope, "reason": "fixture", "idempotency_key": key,
            ]), uri: path)
            XCTAssertEqual(response.statusCode, 200)
        }

        let initialize: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"],
        ]]
        for token in ["personal-agent.secret-a", "project-agent.secret-b"] {
            let response = await router.handle(request("POST", "/mcp", token: token, object: initialize), uri: "/mcp")
            XCTAssertEqual(response.statusCode, 200)
        }
        let list: [String: Any] = ["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": [
            "name": "cofoco_list_todos", "arguments": ["scope": "all"],
        ]]
        let aRequest = request("POST", "/mcp", token: "personal-agent.secret-a", object: list)
        let bRequest = request("POST", "/mcp", token: "project-agent.secret-b", object: list)
        async let a = router.handle(aRequest, uri: "/mcp")
        async let b = router.handle(bRequest, uri: "/mcp")
        let aResponse = await a, bResponse = await b
        let aText = try XCTUnwrap(((json(aResponse)["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String)
        let bText = try XCTUnwrap(((json(bResponse)["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(aText.contains("Private personal"))
        XCTAssertFalse(aText.contains("Private project"))
        XCTAssertTrue(bText.contains("Private project"))
        XCTAssertFalse(bText.contains("Private personal"))
    }
}
