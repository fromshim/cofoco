import Foundation
#if canImport(Security)
import Security
#endif

public enum TodoScope: Codable, Equatable, Sendable {
    case personal
    case project(String)

    public var queryValue: String {
        switch self {
        case .personal: "personal"
        case .project(let id): "project:\(id)"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, id }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "personal": self = .personal
        case "project": self = .project(try values.decode(String.self, forKey: .id))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown Todo scope")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .personal:
            try values.encode("personal", forKey: .kind)
        case .project(let id):
            try values.encode("project", forKey: .kind)
            try values.encode(id, forKey: .id)
        }
    }
}

public enum TodoStatus: String, Codable, CaseIterable, Sendable {
    case open
    case inProgress = "in_progress"
    case done
}

public struct TodoSummary: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let scope: TodoScope
    public let status: TodoStatus
    public let revision: Int64
}

public struct TodoStep: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let isDone: Bool
}

public struct TodoNote: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
}

public struct TodoDetail: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let scope: TodoScope
    public let status: TodoStatus
    public let revision: Int64
    public let steps: [TodoStep]?
    public let notes: [TodoNote]?

    public var summary: TodoSummary {
        TodoSummary(id: id, title: title, scope: scope, status: status, revision: revision)
    }
}

public struct ServiceHealth: Codable, Equatable, Sendable {
    public let status: String
    public let schemaVersion: Int
}

public struct MutationReceipt: Codable, Equatable, Sendable {
    public let outcome: String
    public let todoIds: [String]
    public let revisions: [String: Int64]
    public let proposalId: String?
}

public struct IntegrationReceipt: Codable, Equatable, Sendable {
    public let id: String
    public let outcome: String
    public let mcpUrl: String?
}

public struct IntegrationStatus: Codable, Equatable, Sendable {
    public let id: String
    public let configured: Bool
    public let connected: Bool
    public let mcpUrl: String
}

public enum ServiceClientError: Error, Equatable, LocalizedError {
    case invalidEndpoint
    case missingCredential
    case missingIntegrationCredential
    case invalidCredential
    case serviceUnavailable(String)
    case rejected(statusCode: Int, code: String, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Cofoco service URL must use HTTP on 127.0.0.1."
        case .missingCredential: "Cofoco owner credential was not found in Keychain. Start the local Cofoco service first."
        case .missingIntegrationCredential: "This integration has no local Keychain secret. Grant it through the owner CLI first."
        case .invalidCredential: "Cofoco owner credential in Keychain is empty or invalid."
        case .serviceUnavailable(let detail): "Cofoco service is unavailable: \(detail)"
        case .rejected(let statusCode, let code, let message): "Cofoco rejected the request (\(statusCode), \(code)): \(message)"
        case .invalidResponse: "Cofoco service returned an invalid response."
        }
    }
}

public protocol OwnerTokenProviding: Sendable {
    func ownerToken() throws -> String
}

public protocol IntegrationCredentialManaging: Sendable {
    func secret(for integrationID: String) throws -> String
    func removeSecret(for integrationID: String) throws
}

public struct ServiceHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol ServiceHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse
}

private struct URLSessionServiceTransport: ServiceHTTPTransport, @unchecked Sendable {
    let session: URLSession

    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceClientError.invalidResponse }
        return ServiceHTTPResponse(statusCode: http.statusCode, data: data)
    }
}

public struct ClosureTokenProvider: OwnerTokenProviding {
    private let read: @Sendable () throws -> String

    public init(_ read: @escaping @Sendable () throws -> String) { self.read = read }
    public func ownerToken() throws -> String { try read() }
}

/// Reads the owner-only token installed by the local Cofoco service.
public struct KeychainOwnerTokenProvider: OwnerTokenProviding {
    public static var service: String {
        #if DEBUG
        ProcessInfo.processInfo.environment["COFOCO_KEYCHAIN_SERVICE"] ?? "com.fromshim.cofoco"
        #else
        "com.fromshim.cofoco"
        #endif
    }
    public static let account = "owner-local"

    public init() {}

    public func ownerToken() throws -> String {
        try KeychainCredentialStore.read(account: Self.account)
    }
}

public struct KeychainIntegrationCredentialStore: IntegrationCredentialManaging {
    public init() {}

    public func secret(for integrationID: String) throws -> String {
        try KeychainCredentialStore.read(account: "integration:\(integrationID)", missingError: .missingIntegrationCredential)
    }

    public func removeSecret(for integrationID: String) throws {
        try KeychainCredentialStore.remove(account: "integration:\(integrationID)")
    }
}

private enum KeychainCredentialStore {
    static func read(account: String, missingError: ServiceClientError = .missingCredential) throws -> String {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainOwnerTokenProvider.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw missingError }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw ServiceClientError.invalidCredential
        }
        return value
        #else
        throw missingError
        #endif
    }

    static func remove(account: String) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainOwnerTokenProvider.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ServiceClientError.invalidCredential
        }
        #endif
    }
}

public final class CofocoServiceClient: @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:57321")!

    private let baseURL: URL
    private let transport: ServiceHTTPTransport
    private let tokenProvider: OwnerTokenProviding

    public init(baseURL: URL = defaultBaseURL,
                tokenProvider: OwnerTokenProviding = KeychainOwnerTokenProvider(),
                session: URLSession = .shared,
                transport: ServiceHTTPTransport? = nil) throws {
        guard baseURL.scheme == "http", baseURL.host == "127.0.0.1",
              baseURL.user == nil, baseURL.password == nil,
              baseURL.path.isEmpty || baseURL.path == "/",
              baseURL.query == nil, baseURL.fragment == nil else {
            throw ServiceClientError.invalidEndpoint
        }
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.transport = transport ?? URLSessionServiceTransport(session: session)
    }

    public func health() async throws -> ServiceHealth {
        try await send(path: "/health", method: "GET", authenticated: false,
                       body: Optional<EmptyBody>.none, as: ServiceHealth.self)
    }

    public func listTodos(scope: String = "all", query: String? = nil,
                          status: TodoStatus? = nil, limit: Int = 100) async throws -> [TodoSummary] {
        var components = URLComponents(url: baseURL.appending(path: "/v1/owner/todos"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "scope", value: scope), URLQueryItem(name: "limit", value: String(limit))]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        if let status { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        components.queryItems = items
        guard let url = components.url else { throw ServiceClientError.invalidResponse }
        let response = try await send(url: url, method: "GET", authenticated: true,
                                      body: Optional<EmptyBody>.none, as: TodoListEnvelope.self)
        return response.todos
    }

    public func todo(id: String) async throws -> TodoDetail {
        try await send(path: "/v1/owner/todos/\(Self.pathComponent(id))", method: "GET",
                       authenticated: true, body: Optional<EmptyBody>.none, as: TodoEnvelope.self).todo
    }

    public func createTodo(title: String, scope: TodoScope, reason: String,
                           idempotencyKey: String) async throws -> MutationReceipt {
        let body = CreateTodoBody(title: title, scope: scope, reason: reason, idempotencyKey: idempotencyKey)
        return try await send(path: "/v1/owner/todos", method: "POST", authenticated: true,
                              body: body, as: MutationReceipt.self)
    }

    public func setStatus(id: String, expectedRevision: Int64, status: TodoStatus,
                          reason: String, idempotencyKey: String) async throws -> MutationReceipt {
        let body = UpdateTodoBody(expectedRevision: expectedRevision, status: status,
                                  reason: reason, idempotencyKey: idempotencyKey)
        return try await send(path: "/v1/owner/todos/\(Self.pathComponent(id))", method: "PATCH",
                              authenticated: true, body: body, as: MutationReceipt.self)
    }

    public func grantIntegration(id: String, scopes: [String], canRead: Bool = true,
                                  canWrite: Bool = true, idempotencyKey: String) async throws -> IntegrationReceipt {
        let body = GrantIntegrationBody(id: id, scopes: scopes, canRead: canRead,
                                        canWrite: canWrite, idempotencyKey: idempotencyKey)
        return try await send(path: "/v1/owner/integrations", method: "POST", authenticated: true,
                              body: body, as: IntegrationReceipt.self)
    }

    public func integrationStatus(id: String) async throws -> IntegrationStatus {
        try await send(path: "/v1/owner/integrations/\(Self.pathComponent(id))", method: "GET",
                       authenticated: true, body: Optional<EmptyBody>.none,
                       as: IntegrationStatus.self)
    }

    public func revokeIntegration(id: String, idempotencyKey: String) async throws -> IntegrationReceipt {
        let body = RevokeIntegrationBody(idempotencyKey: idempotencyKey)
        return try await send(path: "/v1/owner/integrations/\(Self.pathComponent(id))", method: "DELETE",
                              authenticated: true, body: body, as: IntegrationReceipt.self)
    }

    private func send<Body: Encodable, Response: Decodable>(path: String, method: String,
                                                             authenticated: Bool, body: Body?,
                                                             as response: Response.Type) async throws -> Response {
        try await send(url: baseURL.appending(path: path), method: method, authenticated: authenticated,
                       body: body, as: response)
    }

    private func send<Body: Encodable, Response: Decodable>(url: URL, method: String,
                                                             authenticated: Bool, body: Body?,
                                                             as response: Response.Type) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            let token = try tokenProvider.ownerToken()
            guard !token.isEmpty, !token.contains("\n") else { throw ServiceClientError.invalidCredential }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        }
        let exchange: ServiceHTTPResponse
        do {
            exchange = try await transport.send(request)
        } catch {
            throw ServiceClientError.serviceUnavailable(error.localizedDescription)
        }
        guard (200..<300).contains(exchange.statusCode) else {
            let payload = try? JSONDecoder().decode(ErrorEnvelope.self, from: exchange.data)
            throw ServiceClientError.rejected(statusCode: exchange.statusCode,
                                              code: payload?.error.code ?? "http_error",
                                              message: payload?.error.message ?? "Request failed")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(Response.self, from: exchange.data) }
        catch { throw ServiceClientError.invalidResponse }
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? value
    }
}

private struct TodoListEnvelope: Decodable { let todos: [TodoSummary] }
private struct TodoEnvelope: Decodable { let todo: TodoDetail }
private struct ErrorEnvelope: Decodable { let error: ServiceAPIError }
private struct ServiceAPIError: Decodable { let code: String; let message: String }

private struct CreateTodoBody: Encodable {
    let title: String
    let scope: TodoScope
    let reason: String
    let idempotencyKey: String
}

private struct UpdateTodoBody: Encodable {
    let expectedRevision: Int64
    let status: TodoStatus
    let reason: String
    let idempotencyKey: String
}

private struct GrantIntegrationBody: Encodable {
    let id: String
    let scopes: [String]
    let canRead: Bool
    let canWrite: Bool
    let idempotencyKey: String
}

private struct RevokeIntegrationBody: Encodable {
    let idempotencyKey: String
}

private struct EmptyBody: Encodable {}
