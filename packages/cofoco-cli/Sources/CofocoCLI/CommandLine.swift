import Foundation

public struct CofocoCommandLine {
    private let client: CofocoServiceClient
    private let integrationCredentials: IntegrationCredentialManaging
    private let write: (String) -> Void
    private let writeError: (String) -> Void
    private let openApplication: () throws -> Void

    public init(client: CofocoServiceClient,
                integrationCredentials: IntegrationCredentialManaging = KeychainIntegrationCredentialStore(),
                write: @escaping (String) -> Void = { print($0) },
                writeError: @escaping (String) -> Void = { fputs($0 + "\n", stderr) },
                openApplication: (() throws -> Void)? = nil) {
        self.client = client
        self.integrationCredentials = integrationCredentials
        self.write = write
        self.writeError = writeError
        self.openApplication = openApplication ?? Self.openInstalledApplication
    }

    @discardableResult
    public func run(_ arguments: [String]) async -> Int32 {
        guard let command = arguments.first else {
            write(Self.usage)
            return 2
        }
        do {
            switch command {
            case "add": try await add(Array(arguments.dropFirst()))
            case "list": try await list(Array(arguments.dropFirst()))
            case "show": try await show(Array(arguments.dropFirst()))
            case "status": try await status(Array(arguments.dropFirst()))
            case "integration": try await integration(Array(arguments.dropFirst()))
            case "open": try open(Array(arguments.dropFirst()))
            case "doctor": try await doctor(Array(arguments.dropFirst()))
            case "help", "--help", "-h": write(Self.usage)
            default: throw CLIError.usage("Unknown command: \(command)")
            }
            return 0
        } catch {
            writeError("cofoco: \(error.localizedDescription)")
            return 1
        }
    }

    private func add(_ arguments: [String]) async throws {
        guard let title = arguments.first, !title.hasPrefix("--") else {
            throw CLIError.usage("Usage: cofoco add <title> [--scope personal|project:<id>] [--reason <text>] [--key <id>] [--json]")
        }
        let options = try Options(Array(arguments.dropFirst()), allowed: ["scope", "reason", "key"])
        let scopeText = options.values["scope"] ?? "personal"
        guard scopeText != "all" else { throw CLIError.usage("A new Todo needs personal or project:<id> scope.") }
        let scope = try TodoScope.parse(scopeText)
        let reason = options.values["reason"] ?? "Added by owner using cofoco CLI"
        let key = options.values["key"] ?? UUID().uuidString
        let result = try await client.createTodo(title: title, scope: scope, reason: reason, idempotencyKey: key)
        try emitMutation(result, key: key, json: options.json)
    }

    private func list(_ arguments: [String]) async throws {
        let options = try Options(arguments, allowed: ["scope", "query", "status", "limit"])
        let scope = options.values["scope"] ?? "all"
        try validateScopeFilter(scope)
        let status = try options.values["status"].map(parseStatus)
        let limit: Int
        if let value = options.values["limit"] {
            guard let parsed = Int(value), (1...200).contains(parsed) else {
                throw CLIError.usage("--limit must be between 1 and 200.")
            }
            limit = parsed
        } else { limit = 100 }
        let todos = try await client.listTodos(scope: scope, query: options.values["query"], status: status, limit: limit)
        if options.json { try writeJSON(todos) }
        else if todos.isEmpty { write("No Todos found.") }
        else {
            for todo in todos {
                write("\(todo.status.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)) \(scopeLabel(todo.scope))  \(todo.title)  [\(todo.id), r\(todo.revision)]")
            }
        }
    }

    private func show(_ arguments: [String]) async throws {
        guard let id = arguments.first, !id.hasPrefix("--") else {
            throw CLIError.usage("Usage: cofoco show <todo-id> [--json]")
        }
        let options = try Options(Array(arguments.dropFirst()), allowed: [])
        let todo = try await client.todo(id: id)
        if options.json { try writeJSON(todo) }
        else {
            write(todo.title)
            write("ID: \(todo.id)")
            write("Status: \(todo.status.rawValue)")
            write("Scope: \(scopeLabel(todo.scope))")
            write("Revision: \(todo.revision)")
            let liveSteps = (todo.steps ?? []).filter { !$0.isDone }
            if !(todo.steps ?? []).isEmpty {
                write("Steps: \(liveSteps.count) open / \(todo.steps!.count) total")
                for step in todo.steps! { write("  [\(step.isDone ? "x" : " ")] \(step.title)") }
            }
            if !(todo.notes ?? []).isEmpty {
                write("Notes:")
                for note in todo.notes! { write("  \(note.text)") }
            }
        }
    }

    private func status(_ arguments: [String]) async throws {
        guard arguments.count >= 2, !arguments[0].hasPrefix("--"), !arguments[1].hasPrefix("--") else {
            throw CLIError.usage("Usage: cofoco status <todo-id> <open|in_progress|done> [--reason <text>] [--key <id>] [--json]")
        }
        let requestedStatus = try parseStatus(arguments[1])
        let options = try Options(Array(arguments.dropFirst(2)), allowed: ["reason", "key"])
        let todo = try await client.todo(id: arguments[0])
        let reason = options.values["reason"] ?? "Status changed by owner using cofoco CLI"
        let key = options.values["key"] ?? UUID().uuidString
        let result = try await client.setStatus(id: todo.id, expectedRevision: todo.revision,
                                                status: requestedStatus, reason: reason,
                                                idempotencyKey: key)
        try emitMutation(result, key: key, json: options.json)
    }

    private func open(_ arguments: [String]) throws {
        let options = try Options(arguments, allowed: [])
        _ = options
        try openApplication()
        write("Opened Cofoco.")
    }

    private func integration(_ arguments: [String]) async throws {
        guard arguments.count >= 2 else {
            throw CLIError.usage("Usage: cofoco integration grant|status|revoke|auth-header <id> ...")
        }
        let action = arguments[0]
        let id = arguments[1]
        try validateIntegrationID(id)
        let remainder = Array(arguments.dropFirst(2))

        switch action {
        case "grant":
            let options = try Options(remainder, allowed: ["scope"], booleanFlags: ["read-only"])
            guard let scopeList = options.values["scope"] else {
                throw CLIError.usage("Usage: cofoco integration grant <id> --scope personal[,project:<id>] [--read-only] [--json]")
            }
            var scopes: [String] = []
            for scope in scopeList.split(separator: ",").map(String.init) {
                try validateIntegrationScope(scope)
                if !scopes.contains(scope) { scopes.append(scope) }
            }
            guard !scopes.isEmpty else { throw CLIError.usage("Grant at least one explicit scope.") }
            let key = UUID().uuidString
            let receipt = try await client.grantIntegration(id: id, scopes: scopes,
                                                            canWrite: !options.flags.contains("read-only"),
                                                            idempotencyKey: key)
            if options.json { try writeJSON(IntegrationMutationOutput(receipt: receipt, idempotencyKey: key)) }
            else {
                write("Integration \(id): \(receipt.outcome)")
                if let mcpURL = receipt.mcpUrl { write("MCP endpoint: \(mcpURL)") }
                write("Credential stored in Keychain; no token was printed.")
            }
        case "status":
            let options = try Options(remainder, allowed: [])
            let status = try await client.integrationStatus(id: id)
            if options.json { try writeJSON(status) }
            else {
                write("Integration \(id): \(status.configured ? "configured" : "not configured")")
                write("Connection: \(status.connected ? "connected" : "not measured")")
                write("MCP endpoint: \(status.mcpUrl)")
            }
        case "revoke":
            let options = try Options(remainder, allowed: [])
            let key = UUID().uuidString
            let receipt = try await client.revokeIntegration(id: id, idempotencyKey: key)
            try integrationCredentials.removeSecret(for: id)
            if options.json { try writeJSON(IntegrationMutationOutput(receipt: receipt, idempotencyKey: key)) }
            else { write("Integration \(id) revoked; its local Keychain secret was removed.") }
        case "auth-header":
            guard remainder.isEmpty else { throw CLIError.usage("Usage: cofoco integration auth-header <id>") }
            let secret = try integrationCredentials.secret(for: id)
            guard !secret.isEmpty, !secret.contains("\n"), !secret.contains("\r") else {
                throw ServiceClientError.invalidCredential
            }
            let data = try JSONSerialization.data(withJSONObject: ["Authorization": "Bearer \(id).\(secret)"])
            guard let output = String(data: data, encoding: .utf8) else { throw ServiceClientError.invalidResponse }
            write(output)
        default:
            throw CLIError.usage("Unknown integration action: \(action)")
        }
    }

    private func doctor(_ arguments: [String]) async throws {
        let options = try Options(arguments, allowed: [])
        do {
            let health = try await client.health()
            guard health.status == "ok" else { throw ServiceClientError.invalidResponse }
            _ = try await client.listTodos(scope: "all", limit: 1)
            if options.json {
                try writeJSON(DoctorResult(ok: true, service: health.status,
                                           schemaVersion: health.schemaVersion, ownerAuthentication: "ok"))
            } else {
                write("PASS service: \(health.status) (schema \(health.schemaVersion))")
                write("PASS owner authentication: accepted")
            }
        } catch {
            if options.json {
                try writeJSON(DoctorResult(ok: false, service: "unavailable", schemaVersion: nil,
                                           ownerAuthentication: "unverified", error: error.localizedDescription))
            } else {
                write("FAIL service/owner connection: \(error.localizedDescription)")
            }
            throw CLIError.doctorFailed
        }
    }

    private func emitMutation(_ result: MutationReceipt, key: String, json: Bool) throws {
        if json { try writeJSON(MutationOutput(receipt: result, idempotencyKey: key)) }
        else {
            let id = result.todoIds.first ?? result.revisions.keys.sorted().first ?? "(no Todo ID)"
            write("\(result.outcome): \(id) (key \(key))")
        }
    }

    private func writeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else { throw ServiceClientError.invalidResponse }
        write(text)
    }

    private func parseStatus(_ value: String) throws -> TodoStatus {
        guard let status = TodoStatus(rawValue: value) else {
            throw CLIError.usage("Status must be open, in_progress, or done.")
        }
        return status
    }

    private func validateScopeFilter(_ scope: String) throws {
        guard scope == "all" || scope == "personal" || scope.hasPrefix("project:") && scope.count > "project:".count else {
            throw CLIError.usage("Scope must be all, personal, or project:<id>.")
        }
    }

    private func validateIntegrationScope(_ scope: String) throws {
        guard scope == "personal" || scope.hasPrefix("project:") && scope.count > "project:".count else {
            throw CLIError.usage("Integration scope must be personal or project:<id>; Personal access is explicit opt-in.")
        }
    }

    private func validateIntegrationID(_ id: String) throws {
        let valid = !id.isEmpty && id.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
        }
        guard valid else { throw CLIError.usage("Integration ID may contain only letters, numbers, underscore, and hyphen.") }
    }

    private func scopeLabel(_ scope: TodoScope) -> String {
        switch scope {
        case .personal: "Personal"
        case .project(let id): "Project \(id)"
        }
    }

    private static func openInstalledApplication() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Cofoco"]
        do { try process.run() }
        catch { throw CLIError.appUnavailable }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError.appUnavailable }
    }

    public static let usage = """
    Cofoco keeps your commitments visible while you and your agents work.

    Usage:
      cofoco add <title> [--scope personal|project:<id>] [--reason <text>] [--key <id>] [--json]
      cofoco list [--scope all|personal|project:<id>] [--query <text>] [--status <state>] [--limit <n>] [--json]
      cofoco show <todo-id> [--json]
      cofoco status <todo-id> <open|in_progress|done> [--reason <text>] [--key <id>] [--json]
      cofoco integration grant <id> --scope personal[,project:<id>] [--read-only] [--json]
      cofoco integration status <id> [--json]
      cofoco integration revoke <id> [--json]
      cofoco integration auth-header <id>
      cofoco open
      cofoco doctor [--json]
    """
}

private struct Options {
    let values: [String: String]
    let flags: Set<String>
    let json: Bool

    init(_ arguments: [String], allowed: Set<String>, booleanFlags: Set<String> = []) throws {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var json = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--json" {
                guard !json else { throw CLIError.usage("--json may only be provided once.") }
                json = true
                index += 1
                continue
            }
            guard argument.hasPrefix("--") else { throw CLIError.usage("Unexpected argument: \(argument)") }
            let name = String(argument.dropFirst(2))
            if booleanFlags.contains(name) {
                guard !flags.contains(name) else { throw CLIError.usage("Option \(argument) may only be used once.") }
                flags.insert(name)
                index += 1
                continue
            }
            guard allowed.contains(name) else { throw CLIError.usage("Unknown option: \(argument)") }
            guard values[name] == nil, index + 1 < arguments.count,
                  !arguments[index + 1].hasPrefix("--") else { throw CLIError.usage("Option \(argument) needs one value and may only be used once.") }
            values[name] = arguments[index + 1]
            index += 2
        }
        self.values = values
        self.flags = flags
        self.json = json
    }
}

private extension TodoScope {
    static func parse(_ value: String) throws -> TodoScope {
        if value == "personal" { return .personal }
        if value.hasPrefix("project:") {
            let id = String(value.dropFirst("project:".count))
            guard !id.isEmpty else { throw CLIError.usage("Project scope needs an ID: project:<id>.") }
            return .project(id)
        }
        throw CLIError.usage("Scope must be personal or project:<id>.")
    }
}

private struct MutationOutput: Encodable {
    let receipt: MutationReceipt
    let idempotencyKey: String
}

private struct IntegrationMutationOutput: Encodable {
    let receipt: IntegrationReceipt
    let idempotencyKey: String
}

private struct DoctorResult: Encodable {
    let ok: Bool
    let service: String
    let schemaVersion: Int?
    let ownerAuthentication: String
    let error: String?

    init(ok: Bool, service: String, schemaVersion: Int?, ownerAuthentication: String, error: String? = nil) {
        self.ok = ok
        self.service = service
        self.schemaVersion = schemaVersion
        self.ownerAuthentication = ownerAuthentication
        self.error = error
    }
}

private enum CLIError: Error, LocalizedError {
    case usage(String)
    case doctorFailed
    case appUnavailable

    var errorDescription: String? {
        switch self {
        case .usage(let message): message
        case .doctorFailed: "Cofoco doctor found a connection problem."
        case .appUnavailable: "Cofoco.app is not installed or could not be opened."
        }
    }
}
