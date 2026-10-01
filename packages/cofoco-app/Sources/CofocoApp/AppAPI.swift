import Foundation
import Security

enum AppScope: Codable, Equatable, Hashable, Sendable {
    case personal
    case project(String)

    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "personal": self = .personal
        case "project": self = .project(try container.decode(String.self, forKey: .id))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown scope")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .personal: try container.encode("personal", forKey: .kind)
        case .project(let id):
            try container.encode("project", forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }

    var query: String {
        switch self {
        case .personal: "personal"
        case .project(let id): "project:\(id)"
        }
    }

    var object: [String: String] {
        switch self {
        case .personal: ["kind": "personal"]
        case .project(let id): ["kind": "project", "id": id]
        }
    }
}

enum AppTodoStatus: String, Codable, Sendable { case open, in_progress, done }

struct AppProject: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var revision: Int64
}

struct AppStep: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var isDone: Bool
    var orderKey: Int64?
}

struct AppNote: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var text: String
    var authorId: String
    var lastEditorId: String?
}

struct AppTodo: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var scope: AppScope
    var status: AppTodoStatus
    var revision: Int64
    var createdAt: String?
    var updatedAt: String?
    var deletedAt: String?
    var steps: [AppStep]?
    var notes: [AppNote]?
    var deletedSteps: [AppStep]?
    var deletedNotes: [AppNote]?
}

struct AppProposalChange: Decodable, Sendable {
    let reservedId: String
    let operation: String
    let before: AppTodo?
    let after: AppTodo
}

struct AppProposal: Decodable, Identifiable, Sendable {
    let id: String
    let actorId: String
    let reason: String
    let state: String
    let createdAt: String
    let changes: [AppProposalChange]
}

struct AppEvent: Codable, Identifiable, Sendable {
    var id: Int64 { cursor }
    let cursor: Int64
    let aggregateId: String
    let actorId: String
    let operation: String
    let reason: String
    let feedback: String
    let resultingRevision: Int64
    let provider: String?

    var operationLabel: String {
        switch operation {
        case "todo.created": "추가됨"
        case "todo.updated": "수정됨"
        case "todo.deleted": "휴지통으로 이동됨"
        case "todo.restored": "복원됨"
        case "proposal.accepted": "제안 승인됨"
        case "proposal.rejected": "제안 거절됨"
        case "proposal.stale": "제안이 오래됨"
        default: operation
        }
    }
}

struct AppIntegration: Decodable, Identifiable, Sendable {
    let id: String
    let scopes: [String]
    let canRead: Bool
    let canWrite: Bool
    let revoked: Bool
}

struct MutationResponse: Decodable, Sendable {
    let outcome: String
    let todoIds: [String]
    let revisions: [String: Int64]
    let proposalId: String?
    let childId: String?
}

struct ProjectMutationResponse: Decodable, Sendable {
    let id: String
    let revision: Int64
    let outcome: String
}

struct IntegrationMutationResponse: Decodable, Sendable {
    let id: String
    let outcome: String
    let mcpUrl: String?
}

enum AppAPIError: LocalizedError {
    case serviceUnavailable
    case missingOwnerCredential
    case rejected(Int, String)
    case invalidResponse
    case versionMismatch

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable: "로컬 서비스에 연결할 수 없어요. 다시 시도해 주세요."
        case .missingOwnerCredential: "앱의 소유자 인증 정보를 찾을 수 없어요. 서비스를 다시 시작해 주세요."
        case .rejected(let code, let message): "요청을 저장하지 못했어요 (\(code): \(message))."
        case .invalidResponse: "로컬 서비스 응답을 읽을 수 없어요."
        case .versionMismatch: "앱과 서비스 버전이 맞지 않아요. Cofoco를 다시 설치해 주세요."
        }
    }
}

@MainActor struct AppAPI {
    static let base = URL(string: "http://127.0.0.1:57321")!
    var session: URLSession = .shared
    var ownerToken: (() throws -> String)?

    private func token() throws -> String {
        if let ownerToken { return try ownerToken() }
        #if DEBUG
        let service = ProcessInfo.processInfo.environment["COFOCO_KEYCHAIN_SERVICE"] ?? "com.fromshim.cofoco"
        #else
        let service = "com.fromshim.cofoco"
        #endif
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: "owner-local",
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, let token = String(data: data, encoding: .utf8) else {
            throw AppAPIError.missingOwnerCredential
        }
        return token
    }

    func request<T: Decodable>(_ method: String = "GET", _ path: String,
                               body: [String: Any]? = nil, authenticated: Bool = true) async throws -> T {
        guard let url = URL(string: path, relativeTo: Self.base) else { throw AppAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated { request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        // A lost response may follow a committed mutation. Replay the identical
        // request/key once; never invent a new key for a transport retry.
        do { (data, response) = try await session.data(for: request) }
        catch {
            guard body?["idempotency_key"] != nil else { throw AppAPIError.serviceUnavailable }
            do { (data, response) = try await session.data(for: request) }
            catch { throw AppAPIError.serviceUnavailable }
        }
        guard let http = response as? HTTPURLResponse else { throw AppAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            throw AppAPIError.rejected(http.statusCode, error?["code"] as? String ?? "unknown")
        }
        let decoder = JSONDecoder()
        let wire = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard wire?["schema_version"] as? Int == 1 else { throw AppAPIError.versionMismatch }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw AppAPIError.invalidResponse }
    }

    func healthy() async -> Bool {
        struct Health: Decodable { let status: String }
        return (try? await request("GET", "/health", authenticated: false) as Health)?.status == "ok"
    }
}

struct TodosEnvelope: Decodable { let todos: [AppTodo] }
struct TodoEnvelope: Decodable { let todo: AppTodo }
struct ProjectsEnvelope: Decodable { let projects: [AppProject] }
struct FoldersEnvelope: Decodable { let folders: [String] }
struct ProposalsEnvelope: Decodable { let proposals: [AppProposal] }
struct ProposalEnvelope: Decodable { let proposal: AppProposal }
struct EventsEnvelope: Decodable { let events: [AppEvent]; let latestCursor: Int64? }
struct IntegrationsEnvelope: Decodable { let integrations: [AppIntegration] }
