import Foundation
import Security
import CofocoCore
import MCP

enum WireError: Error {
    case badRequest
    case unauthorized
    case notFound
}

struct ServiceHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let bodyData: Data?

    init(statusCode: Int, body: Data? = nil) {
        self.statusCode = statusCode
        self.bodyData = body
        self.headers = body == nil ? [:] : ["Content-Type": "application/json; charset=utf-8", "Content-Length": String(body!.count)]
    }

    init(mcp response: HTTPResponse) {
        self.statusCode = response.statusCode
        self.headers = response.headers
        self.bodyData = response.bodyData
    }
}

enum Wire {
    static let schemaVersion = 1
    static let port = 57321
    static let keychainService: String = {
        #if DEBUG
        ProcessInfo.processInfo.environment["COFOCO_KEYCHAIN_SERVICE"] ?? "com.fromshim.cofoco"
        #else
        "com.fromshim.cofoco"
        #endif
    }()

    static func json(_ value: Any) -> ServiceHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return .init(statusCode: 200, body: data)
    }

    static func error(_ code: String, status: Int) -> ServiceHTTPResponse {
        let body: [String: Any] = ["schema_version": schemaVersion, "error": ["code": code, "message": code]]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        return .init(statusCode: status, body: data)
    }

    static func object(_ data: Data?) throws -> [String: Any] {
        guard let data, data.count <= 1_048_576,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WireError.badRequest }
        return value
    }

    static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let text = object[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WireError.badRequest }
        return text
    }

    static func revision(_ object: [String: Any]) throws -> Int64 {
        guard let number = object["expected_revision"] as? NSNumber, number.int64Value >= 1 else { throw WireError.badRequest }
        return number.int64Value
    }

    static func scope(_ object: Any?) throws -> Scope {
        guard let object = object as? [String: Any], let kind = object["kind"] as? String else { throw WireError.badRequest }
        switch kind {
        case "personal": return .personal
        case "project": return .project(try string(object, "id"))
        default: throw WireError.badRequest
        }
    }

    static func scope(_ scope: Scope) -> [String: Any] {
        switch scope {
        case .personal: return ["kind": "personal"]
        case .project(let id): return ["kind": "project", "id": id]
        }
    }

    static func todo(_ todo: Todo, detail: Bool) -> [String: Any] {
        var result: [String: Any] = [
            "id": todo.id, "title": todo.title, "scope": scope(todo.scope),
            "status": todo.status.rawValue, "revision": todo.revision,
        ]
        if detail {
            result["steps"] = todo.steps.filter { $0.deletedAt == nil }.map { ["id": $0.id, "title": $0.title, "is_done": $0.isDone] as [String: Any] }
            result["notes"] = todo.notes.filter { $0.deletedAt == nil }.map { ["id": $0.id, "text": $0.text, "author_id": $0.authorID] as [String: Any] }
        }
        return result
    }

    static func mutation(_ result: MutationResult) -> [String: Any] {
        ["schema_version": schemaVersion, "outcome": result.outcome, "todo_ids": result.todoIDs,
         "revisions": result.revisions, "proposal_id": result.proposalID as Any? ?? NSNull(),
         "event_ids": result.eventIDs, "child_id": result.childID as Any? ?? NSNull()]
    }

    static func status(_ value: String) throws -> TodoStatus {
        guard let status = TodoStatus(rawValue: value) else { throw WireError.badRequest }
        return status
    }

    static func coreError(_ error: Error) -> ServiceHTTPResponse {
        if let error = error as? CoreError {
            switch error {
            case .invalidInput: return self.error("invalid_input", status: 400)
            case .permissionDenied: return self.error("permission_denied", status: 403)
            case .unresolvedScope: return self.error("unresolved_scope", status: 400)
            case .notFound: return self.error("not_found", status: 404)
            case .conflict: return self.error("conflict", status: 409)
            case .idempotencyMismatch: return self.error("idempotency_mismatch", status: 409)
            case .parentClosed: return self.error("parent_closed", status: 409)
            case .parentDeleted: return self.error("parent_deleted", status: 409)
            case .newerSchema, .storeLocked, .storage: return self.error("unavailable", status: 503)
            }
        }
        if error is WireError { return self.error("invalid_input", status: 400) }
        return self.error("unavailable", status: 503)
    }
}

struct KeychainVault: Sendable {
    let testTokens: [String: String]?

    init(testTokens: [String: String]? = nil) { self.testTokens = testTokens }

    func read(account: String) -> String? {
        if let testTokens { return testTokens[account] }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: Wire.keychainService,
                                     kSecAttrAccount as String: account,
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func createIfMissing(account: String) throws -> String {
        if let existing = read(account: account) { return existing }
        if testTokens != nil { throw WireError.unauthorized }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw WireError.unauthorized }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: Wire.keychainService,
                                     kSecAttrAccount as String: account,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                     kSecValueData as String: Data(token.utf8)]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = read(account: account) { return existing }
        guard status == errSecSuccess else { throw WireError.unauthorized }
        return token
    }

    func delete(account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: Wire.keychainService,
                                     kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }

    func equal(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }
}

actor ServiceRouter {
    let core: CoreService
    let vault: KeychainVault
    let ownerToken: String
    private var mcpContexts: [String: CredentialMCP] = [:]

    init(database: URL, vault: KeychainVault = KeychainVault()) throws {
        self.core = try CoreService(path: database)
        self.vault = vault
        self.ownerToken = try vault.createIfMissing(account: "owner-local")
    }

    func handle(_ request: HTTPRequest, uri: String) async -> ServiceHTTPResponse {
        let path = String(uri.split(separator: "?", maxSplits: 1).first ?? "")
        guard let host = request.header("Host"), host == "127.0.0.1:\(Wire.port)" || host == "localhost:\(Wire.port)" else {
            return Wire.error("permission_denied", status: 403)
        }
        if let origin = request.header("Origin"), !["http://127.0.0.1:\(Wire.port)", "http://localhost:\(Wire.port)"].contains(origin) {
            return Wire.error("permission_denied", status: 403)
        }
        if path == "/health" { return Wire.json(["schema_version": 1, "status": "ok"]) }
        if path == "/mcp" {
            guard case .integration(let id)? = integrationPrincipal(request) else { return Wire.error("permission_denied", status: 401) }
            do {
                let context = mcpContext(for: id)
                return ServiceHTTPResponse(mcp: try await context.handle(request))
            } catch { return Wire.coreError(error) }
        }
        guard path.hasPrefix("/v1/owner/"), ownerAuthorized(request) else { return Wire.error("permission_denied", status: 401) }
        do { return try ownerRoute(request, path: path, uri: uri) }
        catch { return Wire.coreError(error) }
    }

    func ownerAuthorized(_ request: HTTPRequest) -> Bool {
        guard let bearer = bearer(request) else { return false }
        return vault.equal(bearer, ownerToken)
    }

    func integrationPrincipal(_ request: HTTPRequest) -> Principal? {
        guard let bearer = bearer(request), let dot = bearer.firstIndex(of: ".") else { return nil }
        let id = String(bearer[..<dot]); let secret = String(bearer[bearer.index(after: dot)...])
        guard !id.isEmpty, !secret.isEmpty, let stored = vault.read(account: "integration:\(id)"),
              vault.equal(secret, stored),
              (try? core.integrationGrantMatchesCredential(id: id,
                    credentialRef: "keychain:\(Wire.keychainService)/integration:\(id)")) == true else { return nil }
        return .integration(id)
    }

    private func mcpContext(for id: String) -> CredentialMCP {
        if let existing = mcpContexts[id] { return existing }
        let context = CredentialMCP(router: self, principal: .integration(id))
        mcpContexts[id] = context
        return context
    }

    private func bearer(_ request: HTTPRequest) -> String? {
        guard let value = request.header("Authorization"), value.hasPrefix("Bearer ") else { return nil }
        return String(value.dropFirst(7))
    }

    private func ownerRoute(_ request: HTTPRequest, path: String, uri: String) throws -> ServiceHTTPResponse {
        let method = request.method.uppercased()
        if path == "/v1/owner/projects", method == "GET" {
            let projects = try core.listProjects(as: .owner)
            return Wire.json(["schema_version": 1, "projects": projects.map {
                ["id": $0.id, "name": $0.name, "revision": $0.revision] as [String: Any]
            }])
        }
        if path == "/v1/owner/projects", method == "POST" {
            let body = try Wire.object(request.body)
            let project = try core.createProject(name: Wire.string(body, "name"), key: Wire.string(body, "idempotency_key"), as: .owner)
            return Wire.json(["schema_version": 1, "id": project.id, "revision": project.revision,
                              "outcome": project.outcome.rawValue])
        }
        if path == "/v1/owner/integrations", method == "POST" {
            let body = try Wire.object(request.body)
            let id = try Wire.string(body, "id")
            guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
                  let rawScopes = body["scopes"] as? [String], !rawScopes.isEmpty else { throw WireError.badRequest }
            let scopes = try rawScopes.map { raw -> Scope in
                if raw == "personal" { return .personal }
                if raw.hasPrefix("project:"), raw.count > 8 { return .project(String(raw.dropFirst(8))) }
                throw WireError.badRequest
            }
            let account = "integration:\(id)"
            let wasPresent = vault.read(account: account) != nil
            _ = try vault.createIfMissing(account: account)
            let result: ProjectMutationResult
            do {
                result = try core.grantIntegration(id: id,
                                                   credentialRef: "keychain:\(Wire.keychainService)/\(account)",
                                                   scopes: scopes,
                                                   canRead: body["can_read"] as? Bool ?? true,
                                                   canWrite: body["can_write"] as? Bool ?? true,
                                                   key: Wire.string(body, "idempotency_key"), as: .owner)
            } catch {
                if !wasPresent { vault.delete(account: account) }
                throw error
            }
            return Wire.json(["schema_version": 1, "id": id, "outcome": result.outcome.rawValue,
                              "mcp_url": "http://127.0.0.1:\(Wire.port)/mcp"])
        }
        if path.hasPrefix("/v1/owner/integrations/"), method == "GET" {
            let id = String(path.dropFirst("/v1/owner/integrations/".count))
            guard !id.isEmpty, !id.contains("/") else { throw WireError.badRequest }
            let hasKey = vault.read(account: "integration:\(id)") != nil
            let activeGrant = (try? core.integrationGrantMatchesCredential(id: id,
                              credentialRef: "keychain:\(Wire.keychainService)/integration:\(id)")) == true
            return Wire.json(["schema_version": 1, "id": id, "configured": hasKey && activeGrant,
                              "connected": false, "mcp_url": "http://127.0.0.1:\(Wire.port)/mcp"])
        }
        if path.hasPrefix("/v1/owner/integrations/"), method == "DELETE" {
            let id = String(path.dropFirst("/v1/owner/integrations/".count))
            guard !id.isEmpty, !id.contains("/") else { throw WireError.badRequest }
            let body = try Wire.object(request.body)
            let result = try core.revokeIntegration(id: id, key: Wire.string(body, "idempotency_key"), as: .owner)
            return Wire.json(["schema_version": 1, "id": id, "outcome": result.outcome.rawValue])
        }
        if path == "/v1/owner/todos", method == "GET" {
            let url = URLComponents(string: "http://127.0.0.1\(uri)")
            let query = Dictionary((url?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
            let scope: Scope?
            switch query["scope"] ?? "all" {
            case "all": scope = nil
            case "personal": scope = .personal
            case let value where value.hasPrefix("project:"): scope = .project(String(value.dropFirst(8)))
            default: throw WireError.badRequest
            }
            let status = try query["status"].map(Wire.status)
            let limit = query["limit"].flatMap(Int.init) ?? 100
            let items = try core.listTodos(scope: scope, query: query["query"], status: status, limit: limit, as: .owner)
            return Wire.json(["schema_version": 1, "todos": items.map { Wire.todo($0, detail: false) }])
        }
        if path == "/v1/owner/todos", method == "POST" {
            let body = try Wire.object(request.body)
            let result = try core.execute(.init(key: Wire.string(body, "idempotency_key"), reason: Wire.string(body, "reason"),
                                                operation: .create(title: Wire.string(body, "title"), scope: Wire.scope(body["scope"]), explicitlyAgreed: true)), as: .owner)
            return Wire.json(Wire.mutation(result))
        }
        if path.hasPrefix("/v1/owner/todos/") {
            let id = String(path.dropFirst("/v1/owner/todos/".count))
            guard !id.isEmpty, !id.contains("/") else { throw WireError.badRequest }
            if method == "GET" { return Wire.json(["schema_version": 1, "todo": Wire.todo(try core.todo(id: id, as: .owner), detail: true)]) }
            if method == "PATCH" {
                let body = try Wire.object(request.body)
                let result = try core.execute(.init(key: Wire.string(body, "idempotency_key"), reason: Wire.string(body, "reason"),
                                                    operation: .update(id: id, expectedRevision: Wire.revision(body),
                                                                       patch: TodoPatch(status: Wire.status(Wire.string(body, "status"))))), as: .owner)
                return Wire.json(Wire.mutation(result))
            }
        }
        throw WireError.notFound
    }
}

/// Isolates each grant, then serializes requests within it. The pinned SDK routes responses
/// by JSON-RPC id and rejects a second initialize on one Server. A fresh initialize gets a
/// fresh SDK Server/transport only after the new handshake succeeds.
actor CredentialMCP {
    private let router: ServiceRouter
    private let principal: Principal
    private var server: Server?
    private var transport: StatelessHTTPServerTransport?
    private var tail: Task<Void, Never>?

    init(router: ServiceRouter, principal: Principal) {
        self.router = router
        self.principal = principal
    }

    func handle(_ request: HTTPRequest) async throws -> HTTPResponse {
        let prior = tail
        let current = Task {
            await prior?.value
            return try await self.serve(request)
        }
        tail = Task { _ = try? await current.value }
        return try await current.value
    }

    private func serve(_ request: HTTPRequest) async throws -> HTTPResponse {
        if isInitialize(request) {
            let (nextServer, nextTransport) = try await makeContext()
            let response = await nextTransport.handleRequest(request)
            if initializedSuccessfully(response) {
                let oldServer = server
                server = nextServer
                transport = nextTransport
                await oldServer?.stop()
            } else {
                await nextServer.stop()
            }
            return response
        }
        if transport == nil {
            let (newServer, newTransport) = try await makeContext()
            server = newServer
            transport = newTransport
        }
        return await transport!.handleRequest(request)
    }

    private func makeContext() async throws -> (Server, StatelessHTTPServerTransport) {
        let nextTransport = StatelessHTTPServerTransport()
        let nextServer = Server(name: "cofoco", version: "0.1.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPTools.configure(nextServer, router: router, principal: principal)
        try await nextServer.start(transport: nextTransport)
        return (nextServer, nextTransport)
    }

    private func isInitialize(_ request: HTTPRequest) -> Bool {
        guard request.method.uppercased() == "POST", let data = request.body,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["jsonrpc"] as? String == "2.0" && object["method"] as? String == "initialize"
    }

    private func initializedSuccessfully(_ response: HTTPResponse) -> Bool {
        guard response.statusCode == 200, let data = response.bodyData,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["result"] != nil && object["error"] == nil
    }
}
