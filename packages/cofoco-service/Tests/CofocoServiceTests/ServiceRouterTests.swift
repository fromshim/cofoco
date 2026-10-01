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

    func testDesktopOwnerRoutesCoverDetailReviewTrashAndCursor() async throws {
        let database = FileManager.default.temporaryDirectory.appendingPathComponent("cofoco-desktop-\(UUID().uuidString).sqlite3")
        let vault = KeychainVault(testTokens: ["owner-local": "owner-secret", "integration:agent-ui": "agent-secret"])
        let router = try ServiceRouter(database: database, vault: vault)
        let owner = "owner-secret"

        let project = await router.handle(request("POST", "/v1/owner/projects", token: owner,
                                                   object: ["name": "UI Project", "idempotency_key": "ui-project"]), uri: "/v1/owner/projects")
        let projectID = try XCTUnwrap(json(project)["id"] as? String)
        let folderPath = FileManager.default.temporaryDirectory.path
        let folderRoute = "/v1/owner/projects/\(projectID)/folders"
        let bound = await router.handle(request("POST", folderRoute, token: owner,
                                                object: ["path": folderPath, "expected_revision": 1, "idempotency_key": "bind-ui"]), uri: folderRoute)
        XCTAssertEqual(bound.statusCode, 200)
        let folders = await router.handle(request("GET", folderRoute, token: owner), uri: folderRoute)
        XCTAssertEqual((try json(folders)["folders"] as? [String])?.count, 1)
        let renamed = await router.handle(request("PATCH", "/v1/owner/projects/\(projectID)", token: owner,
                                                  object: ["name": "Renamed UI", "expected_revision": 2, "idempotency_key": "rename-ui"]),
                                          uri: "/v1/owner/projects/\(projectID)")
        XCTAssertEqual(renamed.statusCode, 200)

        let grant = await router.handle(request("POST", "/v1/owner/integrations", token: owner,
                                                object: ["id": "agent-ui", "scopes": ["personal"], "idempotency_key": "grant-ui"]),
                                        uri: "/v1/owner/integrations")
        XCTAssertEqual(grant.statusCode, 200)
        let grants = await router.handle(request("GET", "/v1/owner/integrations", token: owner), uri: "/v1/owner/integrations")
        XCTAssertEqual((try json(grants)["integrations"] as? [[String: Any]])?.first?["id"] as? String, "agent-ui")

        let create = await router.handle(request("POST", "/v1/owner/todos", token: owner,
                                                 object: ["title": "Original", "scope": ["kind": "personal"],
                                                          "reason": "UI capture", "idempotency_key": "ui-create"]), uri: "/v1/owner/todos")
        let id = try XCTUnwrap((json(create)["todo_ids"] as? [String])?.first)
        let route = "/v1/owner/todos/\(id)"
        let edit = await router.handle(request("PATCH", route, token: owner,
                                               object: ["title": "Edited", "expected_revision": 1,
                                                        "reason": "UI edit", "idempotency_key": "ui-edit"]), uri: route)
        XCTAssertEqual(try json(edit)["outcome"] as? String, "updated")
        let stepRoute = route + "/steps"
        let step = await router.handle(request("POST", stepRoute, token: owner,
                                               object: ["operation": "add", "title": "A milestone", "expected_revision": 2,
                                                        "reason": "UI step", "idempotency_key": "ui-step"]), uri: stepRoute)
        XCTAssertEqual(try json(step)["outcome"] as? String, "updated")
        let noteRoute = route + "/notes"
        let note = await router.handle(request("POST", noteRoute, token: owner,
                                               object: ["operation": "append", "text": "Context", "expected_revision": 3,
                                                        "reason": "UI note", "idempotency_key": "ui-note"]), uri: noteRoute)
        XCTAssertEqual(try json(note)["outcome"] as? String, "updated")
        let detail = await router.handle(request("GET", route, token: owner), uri: route)
        let detailed = try XCTUnwrap(json(detail)["todo"] as? [String: Any])
        XCTAssertEqual(detailed["title"] as? String, "Edited")
        XCTAssertEqual((detailed["steps"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((detailed["notes"] as? [[String: Any]])?.count, 1)

        let initialize: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"],
        ]]
        _ = await router.handle(request("POST", "/mcp", token: "agent-ui.agent-secret", object: initialize), uri: "/mcp")
        let propose = ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "cofoco_update_todo", "arguments": [
            "id": id, "expected_revision": 4, "title": "Agent suggestion", "reason": "Propose title", "idempotency_key": "ui-proposal",
        ]]] as [String: Any]
        let proposalResponse = await router.handle(request("POST", "/mcp", token: "agent-ui.agent-secret", object: propose), uri: "/mcp")
        XCTAssertEqual(proposalResponse.statusCode, 200)
        let pending = await router.handle(request("GET", "/v1/owner/proposals?state=pending", token: owner),
                                          uri: "/v1/owner/proposals?state=pending")
        let proposals = try XCTUnwrap(json(pending)["proposals"] as? [[String: Any]])
        let proposalID = try XCTUnwrap(proposals.first?["id"] as? String)
        XCTAssertEqual((proposals.first?["changes"] as? [[String: Any]])?.count, 1)
        let reviewRoute = "/v1/owner/proposals/\(proposalID)/review"
        let review = await router.handle(request("POST", reviewRoute, token: owner,
                                                 object: ["accept": true, "reason": "UI approved", "idempotency_key": "ui-review"]), uri: reviewRoute)
        XCTAssertEqual(try json(review)["outcome"] as? String, "accepted")
        let updated = await router.handle(request("GET", route, token: owner), uri: route)
        XCTAssertEqual((try json(updated)["todo"] as? [String: Any])?["title"] as? String, "Agent suggestion")

        let eventsRoute = "/v1/owner/events?after=0"
        let feed = await router.handle(request("GET", eventsRoute, token: owner), uri: eventsRoute)
        XCTAssertEqual(feed.statusCode, 200)
        XCTAssertGreaterThanOrEqual((try json(feed)["events"] as? [[String: Any]] ?? []).count, 5)
        let historyRoute = route + "/history"
        let history = await router.handle(request("GET", historyRoute, token: owner), uri: historyRoute)
        XCTAssertTrue((try json(history)["events"] as? [[String: Any]] ?? []).count >= 4)

        let delete = await router.handle(request("DELETE", route, token: owner,
                                                 object: ["expected_revision": 5, "reason": "UI trash", "idempotency_key": "ui-delete"]), uri: route)
        XCTAssertEqual(try json(delete)["outcome"] as? String, "deleted")
        let trashRoute = "/v1/owner/todos?include_deleted=true"
        let trash = await router.handle(request("GET", trashRoute, token: owner), uri: trashRoute)
        XCTAssertNotNil((try json(trash)["todos"] as? [[String: Any]])?.first?["deleted_at"] as? String)
        let restoreRoute = route + "/restore"
        let restore = await router.handle(request("POST", restoreRoute, token: owner,
                                                  object: ["expected_revision": 6, "reason": "UI restore", "idempotency_key": "ui-restore"]), uri: restoreRoute)
        XCTAssertEqual(try json(restore)["outcome"] as? String, "restored")

        let stepID = try XCTUnwrap((detailed["steps"] as? [[String: Any]])?.first?["id"] as? String)
        let noteID = try XCTUnwrap((detailed["notes"] as? [[String: Any]])?.first?["id"] as? String)
        for (childRoute, childID, revision) in [(stepRoute, stepID, 7), (noteRoute, noteID, 8)] {
            let deleted = await router.handle(request("POST", childRoute, token: owner, object: [
                "operation": "delete", "id": childID, "expected_revision": revision,
                "reason": "delete child", "idempotency_key": "delete-\(childID)",
            ]), uri: childRoute)
            XCTAssertEqual(deleted.statusCode, 200)
        }
        let tombstones = await router.handle(request("GET", route, token: owner), uri: route)
        let deletedDetail = try XCTUnwrap(json(tombstones)["todo"] as? [String: Any])
        XCTAssertEqual((deletedDetail["steps"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((deletedDetail["deleted_steps"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((deletedDetail["deleted_notes"] as? [[String: Any]])?.count, 1)
        for (childRoute, childID, revision) in [(stepRoute, stepID, 9), (noteRoute, noteID, 10)] {
            let restored = await router.handle(request("POST", childRoute, token: owner, object: [
                "operation": "restore", "id": childID, "expected_revision": revision,
                "reason": "restore child", "idempotency_key": "restore-\(childID)",
            ]), uri: childRoute)
            XCTAssertEqual(restored.statusCode, 200)
        }
        let deniedFeed = await router.handle(request("GET", eventsRoute, token: "agent-ui.agent-secret"), uri: eventsRoute)
        XCTAssertEqual(deniedFeed.statusCode, 401)
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
