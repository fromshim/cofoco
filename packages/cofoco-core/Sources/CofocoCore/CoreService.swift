import Foundation

/// Metadata supplied by an authenticated adapter. These values never grant authority.
public struct Source: Codable, Equatable, Sendable {
    public var provider: String?
    public var session: String?
    public var proposingActorID: String?
    public init(provider: String? = nil, session: String? = nil) { self.provider = provider; self.session = session }
}

public struct Todo: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var scope: Scope
    public var status: TodoStatus
    public var statusAuthority: String
    public var revision: Int64
    public var orderKey: Int64
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var source: Source
    public var steps: [Step]
    public var notes: [Note]
}

public struct Step: Codable, Equatable, Sendable {
    public var id: String
    public var todoID: String
    public var title: String
    public var isDone: Bool
    public var orderKey: Int64
    public var deletedAt: String?
    public var source: Source
}

public struct Note: Codable, Equatable, Sendable {
    public var id: String
    public var todoID: String
    public var text: String
    public var authorID: String
    public var lastEditorID: String
    public var deletedAt: String?
    public var source: Source
}

public struct TodoPatch: Codable, Equatable, Sendable {
    public var title: String?
    public var scope: Scope?
    public var status: TodoStatus?
    public init(title: String? = nil, scope: Scope? = nil, status: TodoStatus? = nil) {
        self.title = title; self.scope = scope; self.status = status
    }
}

public enum StepOperation: Codable, Equatable, Sendable {
    case add(title: String)
    case edit(id: String, title: String)
    case check(id: String, done: Bool)
    case reorder(ids: [String])
    case delete(id: String)
    case restore(id: String)
}

public enum NoteOperation: Codable, Equatable, Sendable {
    case append(text: String)
    case edit(id: String, text: String)
    case delete(id: String)
    case restore(id: String)
}

public enum CoreOperation: Codable, Equatable, Sendable {
    case create(title: String, scope: Scope, explicitlyAgreed: Bool)
    case update(id: String, expectedRevision: Int64, patch: TodoPatch)
    case delete(id: String, expectedRevision: Int64)
    case restore(id: String, expectedRevision: Int64)
    case step(todoID: String, expectedRevision: Int64, change: StepOperation)
    case note(todoID: String, expectedRevision: Int64, change: NoteOperation)

    var target: String? {
        switch self {
        case .create: return nil
        case .update(let id, _, _), .delete(let id, _), .restore(let id, _): return id
        case .step(let id, _, _), .note(let id, _, _): return id
        }
    }
    var expectedRevision: Int64? {
        switch self {
        case .create: return nil
        case .update(_, let rev, _), .delete(_, let rev), .restore(_, let rev): return rev
        case .step(_, let rev, _), .note(_, let rev, _): return rev
        }
    }
}

public struct MutationRequest: Codable, Equatable, Sendable {
    public var key: String
    public var reason: String
    public var source: Source
    public var operation: CoreOperation
    public init(key: String, reason: String, source: Source = Source(), operation: CoreOperation) {
        self.key = key; self.reason = reason; self.source = source; self.operation = operation
    }
}

public struct MutationResult: Codable, Equatable, Sendable {
    public var outcome: String
    public var todoIDs: [String]
    public var proposalID: String?
    public var revisions: [String: Int64]
    public var eventIDs: [Int64]
    public var childID: String?
    init(_ outcome: String, todoIDs: [String] = [], proposalID: String? = nil,
         revisions: [String: Int64] = [:], eventIDs: [Int64] = [], childID: String? = nil) {
        self.outcome = outcome; self.todoIDs = todoIDs; self.proposalID = proposalID
        self.revisions = revisions; self.eventIDs = eventIDs; self.childID = childID
    }
}

public struct ChangeEvent: Codable, Equatable, Sendable {
    public var cursor: Int64
    public var aggregateID: String
    public var actorID: String
    public var operation: String
    public var before: String?
    public var after: String?
    public var reason: String
    public var resultingRevision: Int64
    public var source: Source
    /// todo/proposal creates visible feedback; detail updates history only.
    public var feedback: String
}

struct ReceiptAccess: Codable { var todoIDs: [String]; var scopes: [Scope]; var proposalID: String? }

/// The only mutation boundary for authenticated UI, CLI and MCP adapters.
/// Principal must come from the adapter's authentication, never decoded from tool input.
public final class CoreService {
    let store: SQLiteStore
    public init(path: URL) throws { self.store = try SQLiteStore(path: path) }
    init(store: SQLiteStore) { self.store = store }

    public func execute(_ request: MutationRequest, as principal: Principal) throws -> MutationResult {
        try store.transaction { _ in
            try validateEnvelope(key: request.key, reason: request.reason)
            // Only review() may attach the authenticated proposing actor to an event.
            guard request.source.proposingActorID == nil else { throw CoreError.invalidInput }
            try authorize(request.operation, as: principal)
            let fingerprint = try encode(request)
            if let replay = try replay(key: request.key, fingerprint: fingerprint, as: principal) { return replay }
            try validate(request.operation, as: principal)
            if try requiresProposal(request.operation, as: principal), try !isNoop(request.operation, as: principal) {
                let result = try createProposal([request.operation], candidates: [], reason: request.reason,
                                                source: request.source, as: principal)
                try receipt(key: request.key, fingerprint: fingerprint, result: result,
                            access: ReceiptAccess(todoIDs: [], scopes: [], proposalID: result.proposalID), as: principal)
                return result
            }
            let result = try apply(request.operation, reservedID: UUID().uuidString,
                                   reason: request.reason, source: request.source, as: principal)
            try receipt(key: request.key, fingerprint: fingerprint, result: result,
                        access: ReceiptAccess(todoIDs: result.todoIDs, scopes: [], proposalID: nil), as: principal)
            return result
        }
    }

    public func todo(id: String, as principal: Principal) throws -> Todo {
        try store.transaction { _ in try accessibleTodo(id, as: principal, write: false) }
    }

    public func listTodos(scope: Scope? = nil, query: String? = nil, status: TodoStatus? = nil,
                          includeDeleted: Bool = false, offset: Int = 0, limit: Int = 100,
                          as principal: Principal) throws -> [Todo] {
        try store.transaction { _ in
            guard offset >= 0, (1...200).contains(limit) else { throw CoreError.invalidInput }
            try authenticated(principal, write: false)
            if let scope { try requireScope(scope, as: principal, write: false) }
            var result: [Todo] = []
            for row in try store.query("SELECT id FROM todos ORDER BY order_key,id") {
                let todo = try loadTodo(row.string("id"))
                guard try store.authorize(principal, scope: todo.scope, write: false),
                      scope == nil || scope == todo.scope,
                      includeDeleted || todo.deletedAt == nil,
                      status == nil || status == todo.status,
                      query == nil || todo.title.localizedCaseInsensitiveContains(query!) else { continue }
                result.append(todo)
            }
            return Array(result.dropFirst(offset).prefix(limit))
        }
    }

    public func history(todoID: String, after cursor: Int64 = 0, limit: Int = 100,
                        as principal: Principal) throws -> [ChangeEvent] {
        try store.transaction { _ in
            guard (1...200).contains(limit), cursor >= 0 else { throw CoreError.invalidInput }
            _ = try accessibleTodo(todoID, as: principal, write: false)
            return try store.query("SELECT * FROM change_events WHERE aggregate_type='todo' AND aggregate_id=? AND cursor>? ORDER BY cursor LIMIT ?",
                                   [.text(todoID), .integer(cursor), .integer(Int64(limit))]).map(event)
        }
    }

    func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
    func now() -> String { ISO8601DateFormatter().string(from: Date()) }
    func validText(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 100_000, !text.contains("\0") else { throw CoreError.invalidInput }
    }
    func validateEnvelope(key: String, reason: String) throws {
        try validText(key); try validText(reason)
        guard key.utf8.count <= 512 else { throw CoreError.invalidInput }
    }
    func authenticated(_ principal: Principal, write: Bool) throws {
        if store.isOwner(principal) { return }
        guard case .integration(let integrationID) = principal,
              let row = try store.query("SELECT * FROM integration_grants WHERE integration_id=? AND revoked_at IS NULL", [.text(integrationID)]).first,
              row.bool("can_read"), !write || row.bool("can_write") else { throw CoreError.permissionDenied }
    }
    func requireScope(_ scope: Scope, as principal: Principal, write: Bool) throws {
        guard try store.authorize(principal, scope: scope, write: write) else { throw CoreError.permissionDenied }
        if case .project(let id) = scope {
            guard try store.scalarInt("SELECT count(*) FROM projects WHERE id=?", [.text(id)]) == 1 else { throw CoreError.invalidInput }
        }
    }
    func accessibleTodo(_ id: String, as principal: Principal, write: Bool) throws -> Todo {
        try authenticated(principal, write: write)
        guard try store.scalarInt("SELECT count(*) FROM todos WHERE id=?", [.text(id)]) == 1 else {
            throw store.isOwner(principal) ? CoreError.notFound : CoreError.permissionDenied
        }
        let todo = try loadTodo(id)
        try requireScope(todo.scope, as: principal, write: write)
        return todo
    }
    func authorize(_ operation: CoreOperation, as principal: Principal) throws {
        try authenticated(principal, write: true)
        if let id = operation.target { _ = try accessibleTodo(id, as: principal, write: true) }
        switch operation {
        case .create(_, let scope, _): try requireScope(scope, as: principal, write: true)
        case .update(_, _, let patch): if let scope = patch.scope { try requireScope(scope, as: principal, write: true) }
        default: break
        }
    }
    func validate(_ operation: CoreOperation, as principal: Principal) throws {
        if case .create(let title, _, _) = operation { try validText(title); return }
        guard let id = operation.target else { throw CoreError.invalidInput }
        let todo = try loadTodo(id)
        guard operation.expectedRevision == todo.revision else { throw CoreError.conflict }
        switch operation {
        case .update(_, _, let patch):
            guard todo.deletedAt == nil else { throw CoreError.parentDeleted }
            guard patch.title != nil || patch.scope != nil || patch.status != nil else { throw CoreError.invalidInput }
            if let title = patch.title { try validText(title) }
        case .restore: break
        case .delete: break
        case .step(_, _, let change):
            try validateParent(todo, as: principal)
            switch change {
            case .add(let title): try validText(title)
            case .edit(let id, let title): try validText(title); _ = try requireStep(id, in: todo, live: true)
            case .check(let id, _), .delete(let id): _ = try requireStep(id, in: todo, live: true)
            case .restore(let id): _ = try requireStep(id, in: todo, live: false)
            case .reorder(let ids):
                let live = todo.steps.filter { $0.deletedAt == nil }.map(\.id)
                guard ids.count == Set(ids).count, Set(ids) == Set(live) else { throw CoreError.invalidInput }
            }
        case .note(_, _, let change):
            try validateParent(todo, as: principal)
            switch change {
            case .append(let text): try validText(text)
            case .edit(let id, let text): try validText(text); _ = try requireNote(id, in: todo, live: true)
            case .delete(let id): _ = try requireNote(id, in: todo, live: true)
            case .restore(let id): _ = try requireNote(id, in: todo, live: false)
            }
        case .create: break
        }
    }
    func validateParent(_ todo: Todo, as principal: Principal) throws {
        guard todo.deletedAt == nil else { throw CoreError.parentDeleted }
        if !store.isOwner(principal), todo.status == .done { throw CoreError.parentClosed }
    }
    func requireStep(_ id: String, in todo: Todo, live: Bool) throws -> Step {
        guard let step = todo.steps.first(where: { $0.id == id }), !live || step.deletedAt == nil else { throw CoreError.notFound }
        return step
    }
    func requireNote(_ id: String, in todo: Todo, live: Bool) throws -> Note {
        guard let note = todo.notes.first(where: { $0.id == id }), !live || note.deletedAt == nil else { throw CoreError.notFound }
        return note
    }
    func requiresProposal(_ operation: CoreOperation, as principal: Principal) throws -> Bool {
        if store.isOwner(principal) { return false }
        switch operation {
        case .create(_, _, let agreed): return !agreed
        case .delete, .restore: return true
        case .step: return false
        case .update(let id, _, let patch):
            let todo = try loadTodo(id)
            if patch.title != nil || patch.scope != nil { return true }
            return !(patch.status == .inProgress && todo.status == .open && todo.statusAuthority != "owner")
        case .note(let id, _, let change):
            switch change {
            case .append: return false
            case .restore: return true
            case .edit(let noteID, _), .delete(let noteID):
                let note = try requireNote(noteID, in: loadTodo(id), live: true)
                return note.authorID != principal.actorID || note.lastEditorID == "owner"
            }
        }
    }

    func isNoop(_ operation: CoreOperation, as principal: Principal) throws -> Bool {
        guard let id = operation.target else { return false }
        let todo = try loadTodo(id)
        switch operation {
        case .update(_, _, let patch):
            return (patch.title == nil || patch.title == todo.title)
                && (patch.scope == nil || patch.scope == todo.scope)
                && (patch.status == nil || patch.status == todo.status)
                && !(patch.status != nil && store.isOwner(principal) && todo.statusAuthority != "owner")
        case .delete: return todo.deletedAt != nil
        case .restore: return todo.deletedAt == nil
        case .note(_, _, .edit(let noteID, let text)):
            let note = try requireNote(noteID, in: todo, live: true)
            return note.text == text && !(store.isOwner(principal) && note.lastEditorID != "owner")
        default: return false
        }
    }

    func loadTodo(_ id: String) throws -> Todo {
        guard let row = try store.query("SELECT * FROM todos WHERE id=?", [.text(id)]).first else { throw CoreError.notFound }
        let steps = try store.query("SELECT * FROM steps WHERE todo_id=? ORDER BY order_key,id", [.text(id)]).map {
            Step(id: $0.string("id"), todoID: id, title: $0.string("title"), isDone: $0.bool("is_done"),
                 orderKey: $0.int64("order_key"), deletedAt: $0.optionalString("deleted_at"), source: try decode(Source.self, $0.string("source_json")))
        }
        let notes = try store.query("SELECT * FROM notes WHERE todo_id=? ORDER BY created_at,id", [.text(id)]).map {
            Note(id: $0.string("id"), todoID: id, text: $0.string("text"), authorID: $0.string("author_id"),
                 lastEditorID: $0.string("last_editor_id"), deletedAt: $0.optionalString("deleted_at"), source: try decode(Source.self, $0.string("source_json")))
        }
        guard let status = TodoStatus(rawValue: row.string("status")) else { throw CoreError.storage("Invalid stored status") }
        return Todo(id: id, title: row.string("title"), scope: row.optionalString("project_id").map(Scope.project) ?? .personal,
                    status: status, statusAuthority: row.string("status_authority"), revision: row.int64("revision"), orderKey: row.int64("order_key"),
                    createdAt: row.string("created_at"), updatedAt: row.string("updated_at"), deletedAt: row.optionalString("deleted_at"),
                    source: try decode(Source.self, row.string("source_json")), steps: steps, notes: notes)
    }
    func projectValue(_ scope: Scope) -> SQLValue { if case .project(let id) = scope { return .text(id) }; return .null }
    func nextOrder() throws -> Int64 { (try store.scalarInt("SELECT max(order_key) FROM todos") ?? 0) + 1 }

    /// Validation runs before this method, including all targets of an atomic group.
    func apply(_ operation: CoreOperation, reservedID: String, reason: String, source: Source,
               as principal: Principal) throws -> MutationResult {
        let timestamp = now(), sourceJSON = try encode(source)
        if case .create(let title, let scope, _) = operation {
            try store.execute("INSERT INTO todos(id,project_id,title,status,status_authority,revision,order_key,created_at,updated_at,source_json) VALUES(?,?,?,'open','default',1,?,?,?,?)",
                              [.text(reservedID), projectValue(scope), .text(title), .integer(try nextOrder()), .text(timestamp), .text(timestamp), .text(sourceJSON)])
            let todo = try loadTodo(reservedID)
            let eventID = try recordEvent(aggregate: reservedID, operation: "todo.created", before: nil, after: encode(todo),
                                          revision: 1, reason: reason, source: source, feedback: "todo", as: principal)
            return MutationResult("created", todoIDs: [reservedID], revisions: [reservedID: 1], eventIDs: [eventID])
        }
        guard let id = operation.target else { throw CoreError.invalidInput }
        let before = try loadTodo(id)
        var changed = false, outcome = "updated", operationName = "", feedback = "todo", childID: String?
        switch operation {
        case .update(_, _, let patch):
            var title = before.title, scope = before.scope, status = before.status, authority = before.statusAuthority, order = before.orderKey
            if let value = patch.title { title = value }
            if let value = patch.scope { scope = value }
            if let value = patch.status {
                status = value
                if store.isOwner(principal) { authority = "owner" }
                else if value != before.status { authority = "agent" }
                if before.status == .done && value != .done { order = try nextOrder() }
            }
            changed = title != before.title || scope != before.scope || status != before.status || authority != before.statusAuthority
            if changed {
                try store.execute("UPDATE todos SET title=?,project_id=?,status=?,status_authority=?,order_key=? WHERE id=?",
                                  [.text(title), projectValue(scope), .text(status.rawValue), .text(authority), .integer(order), .text(id)])
            }
            operationName = "todo.updated"
        case .delete:
            changed = before.deletedAt == nil; outcome = "deleted"; operationName = "todo.deleted"
            if changed { try store.execute("UPDATE todos SET deleted_at=? WHERE id=?", [.text(timestamp), .text(id)]) }
        case .restore:
            changed = before.deletedAt != nil; outcome = "restored"; operationName = "todo.restored"
            if changed { try store.execute("UPDATE todos SET deleted_at=NULL WHERE id=?", [.text(id)]) }
        case .step(_, _, let change):
            feedback = "detail"; operationName = "step.changed"
            switch change {
            case .add(let title):
                childID = reservedID; changed = true
                let order = (before.steps.map(\.orderKey).max() ?? 0) + 1
                try store.execute("INSERT INTO steps(id,todo_id,title,is_done,order_key,source_json,created_at,updated_at) VALUES(?,?,?,0,?,?,?,?)",
                                  [.text(reservedID), .text(id), .text(title), .integer(order), .text(sourceJSON), .text(timestamp), .text(timestamp)])
            case .edit(let stepID, let title):
                changed = try requireStep(stepID, in: before, live: true).title != title; childID = stepID
                if changed { try store.execute("UPDATE steps SET title=?,updated_at=?,source_json=? WHERE id=?", [.text(title), .text(timestamp), .text(sourceJSON), .text(stepID)]) }
            case .check(let stepID, let done):
                changed = try requireStep(stepID, in: before, live: true).isDone != done; childID = stepID
                if changed { try store.execute("UPDATE steps SET is_done=?,updated_at=?,source_json=? WHERE id=?", [.integer(done ? 1 : 0), .text(timestamp), .text(sourceJSON), .text(stepID)]) }
            case .reorder(let ids):
                changed = ids != before.steps.filter { $0.deletedAt == nil }.map(\.id)
                if changed {
                    for (index, stepID) in ids.enumerated() { try store.execute("UPDATE steps SET order_key=?,updated_at=?,source_json=? WHERE id=?", [.integer(Int64(index + 1)), .text(timestamp), .text(sourceJSON), .text(stepID)]) }
                }
            case .delete(let stepID):
                changed = try requireStep(stepID, in: before, live: true).deletedAt == nil; childID = stepID
                if changed { try store.execute("UPDATE steps SET deleted_at=?,updated_at=?,source_json=? WHERE id=?", [.text(timestamp), .text(timestamp), .text(sourceJSON), .text(stepID)]) }
            case .restore(let stepID):
                changed = try requireStep(stepID, in: before, live: false).deletedAt != nil; childID = stepID
                if changed { try store.execute("UPDATE steps SET deleted_at=NULL,updated_at=?,source_json=? WHERE id=?", [.text(timestamp), .text(sourceJSON), .text(stepID)]) }
            }
        case .note(_, _, let change):
            feedback = "detail"; operationName = "note.changed"
            switch change {
            case .append(let text):
                childID = reservedID; changed = true
                try store.execute("INSERT INTO notes(id,todo_id,text,author_id,last_editor_id,source_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)",
                                  [.text(reservedID), .text(id), .text(text), .text(principal.actorID), .text(principal.actorID), .text(sourceJSON), .text(timestamp), .text(timestamp)])
            case .edit(let noteID, let text):
                let note = try requireNote(noteID, in: before, live: true)
                changed = note.text != text || (store.isOwner(principal) && note.lastEditorID != "owner"); childID = noteID
                if changed { try store.execute("UPDATE notes SET text=?,last_editor_id=?,source_json=?,updated_at=? WHERE id=?", [.text(text), .text(principal.actorID), .text(sourceJSON), .text(timestamp), .text(noteID)]) }
            case .delete(let noteID):
                changed = try requireNote(noteID, in: before, live: true).deletedAt == nil; childID = noteID
                if changed { try store.execute("UPDATE notes SET deleted_at=?,last_editor_id=?,source_json=?,updated_at=? WHERE id=?", [.text(timestamp), .text(principal.actorID), .text(sourceJSON), .text(timestamp), .text(noteID)]) }
            case .restore(let noteID):
                changed = try requireNote(noteID, in: before, live: false).deletedAt != nil; childID = noteID
                if changed { try store.execute("UPDATE notes SET deleted_at=NULL,last_editor_id=?,source_json=?,updated_at=? WHERE id=?", [.text(principal.actorID), .text(sourceJSON), .text(timestamp), .text(noteID)]) }
            }
        case .create: throw CoreError.invalidInput
        }
        guard changed else { return MutationResult("noop", todoIDs: [id], revisions: [id: before.revision], childID: childID) }
        try store.execute("UPDATE todos SET revision=revision+1,updated_at=? WHERE id=?", [.text(timestamp), .text(id)])
        let after = try loadTodo(id)
        let eventID = try recordEvent(aggregate: id, operation: operationName, before: encode(before), after: encode(after),
                                     revision: after.revision, reason: reason, source: source, feedback: feedback, as: principal)
        return MutationResult(outcome, todoIDs: [id], revisions: [id: after.revision], eventIDs: [eventID], childID: childID)
    }

    func recordEvent(aggregate: String, type: String = "todo", operation: String, before: String?, after: String?,
                     revision: Int64, reason: String, source: Source, feedback: String, as principal: Principal) throws -> Int64 {
        try store.execute("INSERT INTO change_events(aggregate_type,aggregate_id,actor_id,operation,before_json,after_json,reason,resulting_revision,created_at,source,feedback) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                          [.text(type), .text(aggregate), .text(principal.actorID), .text(operation), before.map(SQLValue.text) ?? .null,
                           after.map(SQLValue.text) ?? .null, .text(reason), .integer(revision), .text(now()), .text(try encode(source)), .text(feedback)])
        return try store.scalarInt("SELECT last_insert_rowid()")!
    }
    func event(_ row: SQLRow) throws -> ChangeEvent {
        ChangeEvent(cursor: row.int64("cursor"), aggregateID: row.string("aggregate_id"), actorID: row.string("actor_id"),
                    operation: row.string("operation"), before: row.optionalString("before_json"), after: row.optionalString("after_json"),
                    reason: row.string("reason"), resultingRevision: row.int64("resulting_revision"), source: try decode(Source.self, row.string("source")), feedback: row.string("feedback"))
    }
    func receipt(key: String, fingerprint: String, result: MutationResult, access: ReceiptAccess, as principal: Principal) throws {
        try store.execute("INSERT INTO operation_receipts(actor_id,key,fingerprint,result_json,access_json,created_at) VALUES(?,?,?,?,?,?)",
                          [.text(principal.actorID), .text(key), .text(fingerprint), .text(try encode(result)), .text(try encode(access)), .text(now())])
    }
    func replay(key: String, fingerprint: String, as principal: Principal) throws -> MutationResult? {
        guard let row = try store.query("SELECT * FROM operation_receipts WHERE actor_id=? AND key=?", [.text(principal.actorID), .text(key)]).first else { return nil }
        if store.isOwner(principal), row.string("fingerprint") != fingerprint { throw CoreError.idempotencyMismatch }
        let access = try decode(ReceiptAccess.self, row.string("access_json"))
        for id in access.todoIDs { _ = try accessibleTodo(id, as: principal, write: true) }
        for scope in access.scopes { try requireScope(scope, as: principal, write: true) }
        if let id = access.proposalID { _ = try accessibleProposal(id, as: principal, write: true) }
        guard row.string("fingerprint") == fingerprint else { throw CoreError.idempotencyMismatch }
        return try decode(MutationResult.self, row.string("result_json"))
    }
}
