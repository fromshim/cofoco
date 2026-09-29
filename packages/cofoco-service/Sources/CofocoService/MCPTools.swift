import Foundation
import CofocoCore
import MCP

enum MCPTools {
    static func configure(_ server: Server, router: ServiceRouter, principal: Principal) async {
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [
                tool("cofoco_get_context", "Resolve a permitted project from a working directory.", ["cwd": ["type": "string"]]),
                tool("cofoco_list_todos", "List permitted Todos; scope is personal, all, or project:<id>.",
                     ["scope": ["type": "string"], "query": ["type": "string"], "status": ["type": "string"], "limit": ["type": "integer"]]),
                tool("cofoco_get_todo", "Read a permitted Todo and its Steps and Notes.", ["id": ["type": "string"]], ["id"]),
                tool("cofoco_create_todo", "Create an agreed Todo, or propose an uncertain commitment.",
                     ["title": ["type": "string"], "scope": ["type": "string"], "reason": ["type": "string"],
                      "idempotency_key": ["type": "string"], "explicitly_agreed": ["type": "boolean"]],
                     ["title", "scope", "reason", "idempotency_key"]),
                tool("cofoco_update_todo", "Request a revision checked Todo title, scope, or status change. Protected changes become proposals.",
                     ["id": ["type": "string"], "expected_revision": ["type": "integer"], "title": ["type": "string"],
                      "scope": ["type": "string"], "status": ["type": "string"], "reason": ["type": "string"],
                      "idempotency_key": ["type": "string"]], ["id", "expected_revision", "reason", "idempotency_key"]),
                tool("cofoco_delete_todo", "Propose soft deletion of a Todo.", standardChange(), standardRequired()),
                tool("cofoco_restore_todo", "Propose restoration of a deleted Todo.", standardChange(), standardRequired()),
                tool("cofoco_update_step", "Maintain a Step on an active Todo.",
                     standardChange().merging(["action": ["type": "string"], "step_id": ["type": "string"],
                                               "title": ["type": "string"], "done": ["type": "boolean"],
                                               "step_ids": ["type": "array"]]) { _, new in new },
                     standardRequired() + ["action"]),
                tool("cofoco_update_note", "Append or edit an authorized Note on an active Todo.",
                     standardChange().merging(["action": ["type": "string"], "note_id": ["type": "string"],
                                               "text": ["type": "string"]]) { _, new in new },
                     standardRequired() + ["action"]),
                tool("cofoco_get_proposal", "Read a permitted change proposal and review state.", ["id": ["type": "string"]], ["id"]),
            ])
        }
        await server.withMethodHandler(CallTool.self) { params in
            let response = await router.callTool(params.name, args: params.arguments ?? [:], principal: principal)
            return .init(content: [.text(text: response.text, annotations: nil, _meta: nil)], isError: response.isError)
        }
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: [String: String]], _ required: [String] = []) -> Tool {
        let valueProperties: [String: Value] = properties.mapValues { fields in
            .object(fields.mapValues { .string($0) })
        }
        return Tool(name: name, description: description, inputSchema: .object([
            "type": .string("object"), "properties": .object(valueProperties),
            "required": .array(required.map { .string($0) }),
            "additionalProperties": .bool(false),
        ]))
    }

    private static func standardChange() -> [String: [String: String]] {
        ["id": ["type": "string"], "expected_revision": ["type": "integer"],
         "reason": ["type": "string"], "idempotency_key": ["type": "string"]]
    }
    private static func standardRequired() -> [String] { ["id", "expected_revision", "reason", "idempotency_key"] }
}

extension ServiceRouter {
    struct ToolReply: Sendable { let text: String; let isError: Bool }

    func callTool(_ name: String, args: [String: Value], principal: Principal) -> ToolReply {
        do {
            let output: [String: Any]
            switch name {
            case "cofoco_get_context":
                let scope = try args["cwd"].flatMap { $0.stringValue }.flatMap { try core.resolveProjectFolder(URL(fileURLWithPath: $0), as: principal) }
                let projects = try core.listProjects(as: principal)
                var choices = projects.map { Wire.scope(.project($0.id)) }
                if (try? core.listTodos(scope: .personal, limit: 1, as: principal)) != nil {
                    choices.insert(Wire.scope(.personal), at: 0)
                }
                output = ["schema_version": 1, "resolved_scope": scope.map(Wire.scope) as Any? ?? NSNull(),
                          "permitted_choices": choices, "capture_policy": "explicit_scope_required"]
            case "cofoco_list_todos":
                let scope = try parseScope(args["scope"]?.stringValue ?? "all")
                let status = try args["status"]?.stringValue.map(Wire.status)
                let limit = args["limit"]?.intValue ?? 100
                let items = try core.listTodos(scope: scope, query: args["query"]?.stringValue, status: status,
                                               limit: limit, as: principal)
                output = ["schema_version": 1, "todos": items.map { Wire.todo($0, detail: false) }]
            case "cofoco_get_todo":
                output = ["schema_version": 1, "todo": Wire.todo(try core.todo(id: required(args, "id"), as: principal), detail: true)]
            case "cofoco_create_todo":
                let result = try core.execute(.init(key: required(args, "idempotency_key"), reason: required(args, "reason"),
                                                    operation: .create(title: required(args, "title"),
                                                                       scope: requiredScope(args, "scope"),
                                                                       explicitlyAgreed: args["explicitly_agreed"]?.boolValue ?? false)), as: principal)
                output = Wire.mutation(result)
            case "cofoco_update_todo":
                let patch = TodoPatch(title: args["title"]?.stringValue,
                                      scope: try args["scope"]?.stringValue.map { _ in try requiredScope(args, "scope") },
                                      status: try args["status"]?.stringValue.map(Wire.status))
                let result = try core.execute(.init(key: required(args, "idempotency_key"), reason: required(args, "reason"),
                                                    operation: .update(id: required(args, "id"), expectedRevision: requiredRevision(args), patch: patch)), as: principal)
                output = Wire.mutation(result)
            case "cofoco_delete_todo", "cofoco_restore_todo":
                let operation: CoreOperation = name == "cofoco_delete_todo"
                    ? .delete(id: try required(args, "id"), expectedRevision: try requiredRevision(args))
                    : .restore(id: try required(args, "id"), expectedRevision: try requiredRevision(args))
                output = Wire.mutation(try core.execute(.init(key: required(args, "idempotency_key"),
                                                            reason: required(args, "reason"), operation: operation), as: principal))
            case "cofoco_update_step":
                let change: StepOperation
                switch try required(args, "action") {
                case "add": change = .add(title: try required(args, "title"))
                case "edit": change = .edit(id: try required(args, "step_id"), title: try required(args, "title"))
                case "check":
                    guard let done = args["done"]?.boolValue else { throw WireError.badRequest }
                    change = .check(id: try required(args, "step_id"), done: done)
                case "reorder":
                    guard let ids = args["step_ids"]?.arrayValue?.compactMap(\.stringValue),
                          ids.count == args["step_ids"]?.arrayValue?.count else { throw WireError.badRequest }
                    change = .reorder(ids: ids)
                case "delete": change = .delete(id: try required(args, "step_id"))
                case "restore": change = .restore(id: try required(args, "step_id"))
                default: throw WireError.badRequest
                }
                output = Wire.mutation(try core.execute(.init(key: required(args, "idempotency_key"), reason: required(args, "reason"),
                                                            operation: .step(todoID: required(args, "id"), expectedRevision: requiredRevision(args), change: change)), as: principal))
            case "cofoco_update_note":
                let change: NoteOperation
                switch try required(args, "action") {
                case "append": change = .append(text: try required(args, "text"))
                case "edit": change = .edit(id: try required(args, "note_id"), text: try required(args, "text"))
                case "delete": change = .delete(id: try required(args, "note_id"))
                case "restore": change = .restore(id: try required(args, "note_id"))
                default: throw WireError.badRequest
                }
                output = Wire.mutation(try core.execute(.init(key: required(args, "idempotency_key"), reason: required(args, "reason"),
                                                            operation: .note(todoID: required(args, "id"), expectedRevision: requiredRevision(args), change: change)), as: principal))
            case "cofoco_get_proposal":
                let proposal = try core.proposal(id: required(args, "id"), as: principal)
                output = ["schema_version": 1, "id": proposal.id, "state": proposal.state, "reason": proposal.reason,
                          "todo_ids": proposal.result?.todoIDs ?? [],
                          "changes": proposal.changes.map { change in
                    ["reserved_id": change.reservedID,
                     "before": change.before.map { Wire.todo($0, detail: false) } as Any? ?? NSNull(),
                     "after": Wire.todo(change.after, detail: false)] as [String: Any]
                }]
            default: return failure("invalid_input")
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
            return .init(text: String(decoding: data, as: UTF8.self), isError: false)
        } catch {
            return failure(errorCode(error))
        }
    }

    private func required(_ args: [String: Value], _ key: String) throws -> String {
        guard let value = args[key]?.stringValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WireError.badRequest }
        return value
    }
    private func requiredRevision(_ args: [String: Value]) throws -> Int64 {
        guard let value = args["expected_revision"]?.intValue, value >= 1 else { throw WireError.badRequest }
        return Int64(value)
    }
    private func requiredScope(_ args: [String: Value], _ key: String) throws -> Scope {
        try parseScope(required(args, key)) ?? { throw WireError.badRequest }()
    }
    private func parseScope(_ raw: String) throws -> Scope? {
        if raw == "all" { return nil }
        if raw == "personal" { return .personal }
        if raw.hasPrefix("project:"), raw.count > 8 { return .project(String(raw.dropFirst(8))) }
        throw WireError.badRequest
    }
    private func errorCode(_ error: Error) -> String {
        if let error = error as? CoreError {
            switch error {
            case .invalidInput: "invalid_input"
            case .permissionDenied: "permission_denied"
            case .unresolvedScope: "unresolved_scope"
            case .notFound: "not_found"
            case .conflict: "conflict"
            case .idempotencyMismatch: "idempotency_mismatch"
            case .parentClosed: "parent_closed"
            case .parentDeleted: "parent_deleted"
            case .newerSchema, .storeLocked, .storage: "unavailable"
            }
        } else { "invalid_input" }
    }
    private func failure(_ code: String) -> ToolReply {
        .init(text: "{\"schema_version\":1,\"error\":{\"code\":\"\(code)\"}}", isError: true)
    }
}
