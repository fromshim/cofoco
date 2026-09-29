import Foundation

public struct ProposedChange: Codable, Equatable, Sendable {
    public var operation: CoreOperation
    /// Reserved application identity, including a proposed new Todo/child.
    public var reservedID: String
    public var before: Todo?
    public var after: Todo
}

public struct ChangeProposal: Codable, Equatable, Sendable {
    public var id: String
    public var actorID: String
    public var reason: String
    public var source: Source
    public var changes: [ProposedChange]
    public var candidateIDs: [String]
    public var state: String
    public var createdAt: String
    public var reviewedAt: String?
    public var reviewerID: String?
    public var result: MutationResult?
}

struct ProposalPayload: Codable {
    var changes: [ProposedChange]
    var candidates: [String]
    var source: Source
}
struct ProposalRequest: Codable {
    var operations: [CoreOperation]
    var candidateIDs: [String]
    var reason: String
    var source: Source
}
struct ReviewRequest: Codable { var proposalID: String; var accept: Bool; var reason: String }

extension CoreService {
    public func propose(_ operations: [CoreOperation], candidateIDs: [String] = [], key: String,
                        reason: String, source: Source = Source(), as principal: Principal) throws -> MutationResult {
        try store.transaction { _ in
            try validateEnvelope(key: key, reason: reason)
            guard source.proposingActorID == nil else { throw CoreError.invalidInput }
            guard !operations.isEmpty, operations.count <= 100, candidateIDs.count <= 100,
                  Set(candidateIDs).count == candidateIDs.count else { throw CoreError.invalidInput }
            for operation in operations { try authorize(operation, as: principal) }
            for id in candidateIDs { _ = try accessibleTodo(id, as: principal, write: false) }
            let fingerprint = try encode(ProposalRequest(operations: operations, candidateIDs: candidateIDs, reason: reason, source: source))
            if let result = try replay(key: key, fingerprint: fingerprint, as: principal) { return result }
            for operation in operations { try validate(operation, as: principal) }
            let result = try createProposal(operations, candidates: candidateIDs, reason: reason, source: source, as: principal)
            try receipt(key: key, fingerprint: fingerprint, result: result,
                        access: ReceiptAccess(todoIDs: [], scopes: [], proposalID: result.proposalID), as: principal)
            return result
        }
    }

    public func proposal(id: String, as principal: Principal) throws -> ChangeProposal {
        try store.transaction { _ in try accessibleProposal(id, as: principal, write: false) }
    }

    public func listProposals(state: String? = nil, offset: Int = 0, limit: Int = 100,
                              as principal: Principal) throws -> [ChangeProposal] {
        try store.transaction { _ in
            guard offset >= 0, (1...200).contains(limit), state == nil || ["pending", "accepted", "rejected", "stale"].contains(state!) else { throw CoreError.invalidInput }
            try authenticated(principal, write: false)
            var proposals: [ChangeProposal] = []
            for row in try store.query("SELECT id FROM change_proposals ORDER BY created_at,id") {
                do {
                    let proposal = try accessibleProposal(row.string("id"), as: principal, write: false)
                    if state == nil || proposal.state == state { proposals.append(proposal) }
                } catch CoreError.permissionDenied { continue }
            }
            return Array(proposals.dropFirst(offset).prefix(limit))
        }
    }

    /// Available only to an authenticated owner adapter. Integrations cannot review, even their own proposals.
    /// A failed freshness/permission check durably marks the preview stale and returns outcome="stale".
    public func review(proposalID: String, accept: Bool, key: String, reason: String,
                       as principal: Principal) throws -> MutationResult {
        try store.transaction { _ in
            guard store.isOwner(principal) else { throw CoreError.permissionDenied }
            try validateEnvelope(key: key, reason: reason)
            let fingerprint = try encode(ReviewRequest(proposalID: proposalID, accept: accept, reason: reason))
            let proposal = try accessibleProposal(proposalID, as: principal, write: true)
            if let result = try replay(key: key, fingerprint: fingerprint, as: principal) { return result }
            if proposal.state != "pending" {
                // Decisions are terminal, including a later request with a new delivery key.
                guard let result = proposal.result else { throw CoreError.storage("Missing proposal review result") }
                try receipt(key: key, fingerprint: fingerprint, result: result,
                            access: ReceiptAccess(todoIDs: [], scopes: [], proposalID: proposalID), as: principal)
                return result
            }
            var state = accept ? "accepted" : "rejected"
            if accept {
                let proposer: Principal = proposal.actorID == "owner" ? .owner : .integration(String(proposal.actorID.dropFirst("integration:".count)))
                do {
                    for change in proposal.changes {
                        try authorize(change.operation, as: proposer)
                        if let before = change.before { try requireScope(before.scope, as: proposer, write: true) }
                        try validate(change.operation, as: proposer)
                    }
                    for id in proposal.candidateIDs { _ = try accessibleTodo(id, as: proposer, write: false) }
                } catch CoreError.permissionDenied { state = "stale" }
                  catch CoreError.conflict { state = "stale" }
                  catch CoreError.parentClosed { state = "stale" }
                  catch CoreError.parentDeleted { state = "stale" }
                  catch CoreError.notFound { state = "stale" }
                  catch CoreError.invalidInput { state = "stale" }
            }
            var result = MutationResult(state, proposalID: proposalID)
            if state == "accepted" {
                var source = proposal.source; source.proposingActorID = proposal.actorID
                for change in proposal.changes {
                    let operation = try rebased(change.operation)
                    try validate(operation, as: principal)
                    let applied = try apply(operation, reservedID: change.reservedID, reason: proposal.reason, source: source, as: principal)
                    result.todoIDs.append(contentsOf: applied.todoIDs.filter { !result.todoIDs.contains($0) })
                    result.revisions.merge(applied.revisions) { _, newest in newest }
                    result.eventIDs.append(contentsOf: applied.eventIDs)
                }
            }
            var source = proposal.source; source.proposingActorID = proposal.actorID
            let reviewEvent = try recordEvent(aggregate: proposalID, type: "proposal", operation: "proposal.\(state)",
                                              before: encode(proposal), after: state, revision: 0, reason: reason,
                                              source: source, feedback: "detail", as: principal)
            result.eventIDs.append(reviewEvent)
            try store.execute("UPDATE change_proposals SET state=?,reviewed_at=?,reviewer_id=?,result_json=? WHERE id=?",
                              [.text(state), .text(now()), .text(principal.actorID), .text(try encode(result)), .text(proposalID)])
            try receipt(key: key, fingerprint: fingerprint, result: result,
                        access: ReceiptAccess(todoIDs: [], scopes: [], proposalID: proposalID), as: principal)
            return result
        }
    }

    func createProposal(_ operations: [CoreOperation], candidates: [String], reason: String,
                        source: Source, as principal: Principal) throws -> MutationResult {
        let proposalID = UUID().uuidString
        // Simulate within a savepoint to capture the exact grouped before/after preview, including
        // reserved identities and revisions. No simulated state/event survives savepoint rollback.
        var changes: [ProposedChange] = []
        try store.execute("SAVEPOINT proposal_preview")
        do {
            for operation in operations {
                let before = try operation.target.map(loadTodo)
                let reserved = UUID().uuidString
                let adjusted = try rebased(operation)
                try validate(adjusted, as: .owner)
                _ = try apply(adjusted, reservedID: reserved, reason: reason, source: source, as: .owner)
                let after = try loadTodo(operation.target ?? reserved)
                // Keep the original request revision, while before includes the prior group operation.
                changes.append(ProposedChange(operation: operation, reservedID: reserved, before: before, after: after))
            }
            try store.execute("ROLLBACK TO proposal_preview")
            try store.execute("RELEASE proposal_preview")
        } catch {
            _ = try? store.execute("ROLLBACK TO proposal_preview")
            _ = try? store.execute("RELEASE proposal_preview")
            throw error
        }
        let payload = ProposalPayload(changes: changes, candidates: candidates, source: source)
        try store.execute("INSERT INTO change_proposals(id,actor_id,payload_json,preview_json,reason,state,created_at) VALUES(?,?,?,?,?,'pending',?)",
                          [.text(proposalID), .text(principal.actorID), .text(try encode(payload)), .text(try encode(changes)), .text(reason), .text(now())])
        var recorded: Set<String> = []
        for operation in operations {
            if let id = operation.target, recorded.insert(id).inserted, let revision = operation.expectedRevision {
                try store.execute("INSERT INTO proposal_targets(proposal_id,todo_id,expected_revision) VALUES(?,?,?)",
                                  [.text(proposalID), .text(id), .integer(revision)])
            }
        }
        let eventID = try recordEvent(aggregate: proposalID, type: "proposal", operation: "proposal.created", before: nil,
                                     after: encode(payload), revision: 0, reason: reason, source: source, feedback: "proposal", as: principal)
        return MutationResult("proposed", proposalID: proposalID, eventIDs: [eventID])
    }

    func accessibleProposal(_ id: String, as principal: Principal, write: Bool) throws -> ChangeProposal {
        try authenticated(principal, write: write)
        guard let row = try store.query("SELECT * FROM change_proposals WHERE id=?", [.text(id)]).first else {
            throw store.isOwner(principal) ? CoreError.notFound : CoreError.permissionDenied
        }
        let payload = try decode(ProposalPayload.self, row.string("payload_json"))
        for change in payload.changes {
            if let target = change.operation.target { _ = try accessibleTodo(target, as: principal, write: write) }
            if case .create(_, let scope, _) = change.operation { try requireScope(scope, as: principal, write: write) }
            if case .update(_, _, let patch) = change.operation, let scope = patch.scope { try requireScope(scope, as: principal, write: write) }
            // Immutable previews retain former scope contents after moves and terminal decisions.
            if let before = change.before { try requireScope(before.scope, as: principal, write: write) }
            try requireScope(change.after.scope, as: principal, write: write)
            if row.string("state") == "accepted", change.operation.target == nil {
                _ = try accessibleTodo(change.reservedID, as: principal, write: write)
            }
        }
        for candidate in payload.candidates { _ = try accessibleTodo(candidate, as: principal, write: false) }
        return ChangeProposal(id: id, actorID: row.string("actor_id"), reason: row.string("reason"), source: payload.source,
                              changes: payload.changes, candidateIDs: payload.candidates, state: row.string("state"), createdAt: row.string("created_at"),
                              reviewedAt: row.optionalString("reviewed_at"), reviewerID: row.optionalString("reviewer_id"),
                              result: try row.optionalString("result_json").map { try decode(MutationResult.self, $0) })
    }

    func rebased(_ operation: CoreOperation) throws -> CoreOperation {
        guard let id = operation.target else { return operation }
        let revision = try loadTodo(id).revision
        switch operation {
        case .update(let id, _, let patch): return .update(id: id, expectedRevision: revision, patch: patch)
        case .delete(let id, _): return .delete(id: id, expectedRevision: revision)
        case .restore(let id, _): return .restore(id: id, expectedRevision: revision)
        case .step(let id, _, let change): return .step(todoID: id, expectedRevision: revision, change: change)
        case .note(let id, _, let change): return .note(todoID: id, expectedRevision: revision, change: change)
        case .create: return operation
        }
    }
}
