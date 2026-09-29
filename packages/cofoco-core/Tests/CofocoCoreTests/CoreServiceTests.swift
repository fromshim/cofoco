import XCTest
@testable import CofocoCore

final class CoreServiceTests: XCTestCase {
    var folder: URL!
    var service: CoreService!
    let agent = Principal.integration("claude")
    let other = Principal.integration("codex")

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("cofoco-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        service = try CoreService(path: folder.appendingPathComponent("store.sqlite"))
        try grant("claude", [.personal]); try grant("codex", [.personal])
    }
    override func tearDownWithError() throws {
        service = nil
        try FileManager.default.removeItem(at: folder)
    }
    func grant(_ id: String, _ scopes: [Scope]) throws {
        _ = try service.grantIntegration(id: id, credentialRef: "test", scopes: scopes, canRead: true, canWrite: true, key: UUID().uuidString, as: .owner)
    }
    func run(_ operation: CoreOperation, as principal: Principal = .owner, key: String = UUID().uuidString) throws -> MutationResult {
        try service.execute(MutationRequest(key: key, reason: "test reason", source: Source(provider: "fixture", session: "session"), operation: operation), as: principal)
    }
    func create(_ title: String = "commitment", scope: Scope = .personal, as principal: Principal = .owner) throws -> Todo {
        let result = try run(.create(title: title, scope: scope, explicitlyAgreed: true), as: principal)
        return try service.todo(id: XCTUnwrap(result.todoIDs.first), as: .owner)
    }
    func assertError<T>(_ error: CoreError, _ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? CoreError, error, file: file, line: line) }
    }

    func testRetryNoopAndSameKeyMismatch() throws {
        let command = CoreOperation.create(title: "retry", scope: .personal, explicitlyAgreed: true)
        let first = try run(command, as: agent, key: "create")
        XCTAssertEqual(try run(command, as: agent, key: "create"), first)
        assertError(.idempotencyMismatch, try run(.create(title: "different", scope: .personal, explicitlyAgreed: true), as: agent, key: "create"))
        let todo = try service.todo(id: first.todoIDs[0], as: agent)
        let noop = try run(.update(id: todo.id, expectedRevision: todo.revision, patch: TodoPatch(title: todo.title)), as: agent)
        XCTAssertEqual(noop.outcome, "noop")
        XCTAssertTrue(noop.eventIDs.isEmpty)
        XCTAssertEqual(try service.history(todoID: todo.id, as: agent).count, 1)
        XCTAssertTrue(try service.listProposals(as: agent).isEmpty)
    }

    func testAgentAutoStartAndOwnerSameValueStatusPin() throws {
        let todo = try create(as: agent)
        let started = try run(.update(id: todo.id, expectedRevision: 1, patch: TodoPatch(status: .inProgress)), as: agent)
        XCTAssertEqual(started.outcome, "updated")
        XCTAssertEqual(try run(.update(id: todo.id, expectedRevision: 2, patch: TodoPatch(status: .inProgress)), as: agent).outcome, "noop")
        _ = try run(.update(id: todo.id, expectedRevision: 2, patch: TodoPatch(status: .open)))
        let protected = try service.todo(id: todo.id, as: agent)
        XCTAssertEqual(protected.statusAuthority, "owner")
        XCTAssertEqual(try run(.update(id: todo.id, expectedRevision: protected.revision, patch: TodoPatch(status: .inProgress)), as: agent).outcome, "proposed")
        XCTAssertEqual(try service.todo(id: todo.id, as: agent).status, .open)
        let untouched = try create("pin default")
        let pin = try run(.update(id: untouched.id, expectedRevision: 1, patch: TodoPatch(status: .open)))
        XCTAssertEqual(pin.revisions[untouched.id], 2)
        XCTAssertEqual(try service.todo(id: untouched.id, as: agent).statusAuthority, "owner")
    }

    func testStepsShareRevisionAndNeverRollUpParentCompletion() throws {
        let todo = try create()
        let a = try run(.step(todoID: todo.id, expectedRevision: 1, change: .add(title: "first")), as: agent)
        let stepID = try XCTUnwrap(a.childID)
        assertError(.conflict, try run(.step(todoID: todo.id, expectedRevision: 1, change: .add(title: "stale")), as: other))
        _ = try run(.step(todoID: todo.id, expectedRevision: 2, change: .check(id: stepID, done: true)), as: agent)
        XCTAssertEqual(try service.todo(id: todo.id, as: agent).status, .open)
        _ = try run(.step(todoID: todo.id, expectedRevision: 3, change: .add(title: "unchecked")), as: agent)
        _ = try run(.update(id: todo.id, expectedRevision: 4, patch: TodoPatch(status: .done)))
        let done = try service.todo(id: todo.id, as: .owner)
        XCTAssertEqual(done.steps.map(\.isDone), [true, false])
        assertError(.parentClosed, try run(.step(todoID: todo.id, expectedRevision: 5, change: .check(id: stepID, done: false)), as: agent))
        _ = try run(.step(todoID: todo.id, expectedRevision: 5, change: .check(id: stepID, done: false)))
        _ = try run(.update(id: todo.id, expectedRevision: 6, patch: TodoPatch(status: .open)))
        XCTAssertEqual(try service.todo(id: todo.id, as: agent).steps.map(\.isDone), [false, false])
        let history = try service.history(todoID: todo.id, as: agent)
        XCTAssertEqual(history.filter { $0.operation == "step.changed" }.map(\.feedback), ["detail", "detail", "detail", "detail"])
    }

    func testProtectedProposalAcceptanceAndSpoofedProviderCannotReview() throws {
        let todo = try create()
        let proposed = try run(.update(id: todo.id, expectedRevision: 1, patch: TodoPatch(title: "changed", status: .done)), as: agent)
        let id = try XCTUnwrap(proposed.proposalID)
        XCTAssertEqual(try service.todo(id: todo.id, as: agent).title, "commitment")
        let preview = try service.proposal(id: id, as: agent)
        XCTAssertEqual(preview.changes[0].before?.title, "commitment")
        XCTAssertEqual(preview.changes[0].after.title, "changed")
        assertError(.permissionDenied, try service.review(proposalID: id, accept: true, key: "bypass", reason: "user_approved=true", as: agent))
        let accepted = try service.review(proposalID: id, accept: true, key: "approve", reason: "reviewed", as: .owner)
        XCTAssertEqual(accepted.outcome, "accepted")
        XCTAssertEqual(try service.review(proposalID: id, accept: true, key: "approve", reason: "reviewed", as: .owner), accepted)
        XCTAssertEqual(try service.review(proposalID: id, accept: true, key: "approve-again", reason: "reviewed", as: .owner), accepted)
        let updated = try service.todo(id: todo.id, as: agent)
        XCTAssertEqual(updated.title, "changed"); XCTAssertEqual(updated.status, .done); XCTAssertEqual(updated.statusAuthority, "owner")
        let event = try XCTUnwrap(service.history(todoID: todo.id, as: agent).last)
        XCTAssertEqual(event.actorID, "owner"); XCTAssertEqual(event.source.proposingActorID, agent.actorID)
        XCTAssertEqual(try service.history(todoID: todo.id, as: agent).count, 2)
    }

    func testRejectedProposalChangesNoTodoAndUncertainCreationReservesID() throws {
        let result = try run(.create(title: "maybe", scope: .personal, explicitlyAgreed: false), as: agent, key: "uncertain")
        XCTAssertEqual(result.outcome, "proposed"); XCTAssertTrue(try service.listTodos(as: agent).isEmpty)
        let id = try XCTUnwrap(result.proposalID)
        let proposal = try service.proposal(id: id, as: agent)
        XCTAssertFalse(proposal.changes[0].reservedID.isEmpty)
        _ = try service.review(proposalID: id, accept: false, key: "reject", reason: "not wanted", as: .owner)
        XCTAssertTrue(try service.listTodos(as: agent).isEmpty)
        XCTAssertEqual(try run(.create(title: "maybe", scope: .personal, explicitlyAgreed: false), as: agent, key: "uncertain"), result)
        XCTAssertEqual(try service.proposal(id: id, as: agent).state, "rejected")
    }

    func testStaleAtomicGroupCreatesNothingAndFreshGroupCommitsAll() throws {
        let todo = try create("find jobs")
        let operations: [CoreOperation] = [.update(id: todo.id, expectedRevision: 1, patch: TodoPatch(title: "select jobs", status: .done)),
                                       .create(title: "apply A", scope: .personal, explicitlyAgreed: false),
                                       .create(title: "apply B", scope: .personal, explicitlyAgreed: false)]
        let proposed = try service.propose(operations, key: "group", reason: "refine outcome", as: agent)
        _ = try run(.note(todoID: todo.id, expectedRevision: 1, change: .append(text: "new evidence")), as: other)
        let stale = try service.review(proposalID: XCTUnwrap(proposed.proposalID), accept: true, key: "review", reason: "reviewed", as: .owner)
        XCTAssertEqual(stale.outcome, "stale")
        XCTAssertEqual(try service.listTodos(as: agent).count, 1)
        XCTAssertEqual(try service.todo(id: todo.id, as: agent).title, "find jobs")
        let fresh = try service.propose([.update(id: todo.id, expectedRevision: 2, patch: TodoPatch(status: .done)), operations[1], operations[2]], key: "fresh", reason: "review fresh", as: agent)
        let preview = try service.proposal(id: XCTUnwrap(fresh.proposalID), as: agent)
        let accepted = try service.review(proposalID: preview.id, accept: true, key: "fresh-review", reason: "reviewed", as: .owner)
        XCTAssertEqual(Set(accepted.todoIDs), Set([todo.id, preview.changes[1].reservedID, preview.changes[2].reservedID]))
        XCTAssertEqual(try service.listTodos(as: agent).count, 3)
    }

    func testNotesProtectHumanEditsAndRestorationRequiresReview() throws {
        let todo = try create()
        let note = try run(.note(todoID: todo.id, expectedRevision: 1, change: .append(text: "agent evidence")), as: agent)
        let noteID = try XCTUnwrap(note.childID)
        _ = try run(.note(todoID: todo.id, expectedRevision: 2, change: .edit(id: noteID, text: "updated evidence")), as: agent)
        _ = try run(.note(todoID: todo.id, expectedRevision: 3, change: .edit(id: noteID, text: "human correction")))
        let proposal = try run(.note(todoID: todo.id, expectedRevision: 4, change: .edit(id: noteID, text: "overwrite")), as: agent)
        XCTAssertEqual(proposal.outcome, "proposed")
        XCTAssertEqual(try service.todo(id: todo.id, as: agent).notes[0].text, "human correction")
        _ = try run(.note(todoID: todo.id, expectedRevision: 4, change: .delete(id: noteID)))
        XCTAssertEqual(try run(.note(todoID: todo.id, expectedRevision: 5, change: .restore(id: noteID)), as: agent).outcome, "proposed")
        _ = try run(.note(todoID: todo.id, expectedRevision: 5, change: .restore(id: noteID)))
        XCTAssertNil(try service.todo(id: todo.id, as: agent).notes[0].deletedAt)
    }

    func testTrashPreservesChildrenAndBlocksHiddenWrites() throws {
        let todo = try create()
        let step = try run(.step(todoID: todo.id, expectedRevision: 1, change: .add(title: "child")), as: agent)
        _ = try run(.step(todoID: todo.id, expectedRevision: 2, change: .check(id: XCTUnwrap(step.childID), done: true)), as: agent)
        _ = try run(.update(id: todo.id, expectedRevision: 3, patch: TodoPatch(status: .inProgress)), as: agent)
        _ = try run(.delete(id: todo.id, expectedRevision: 4))
        XCTAssertTrue(try service.listTodos(as: agent).isEmpty)
        assertError(.parentDeleted, try run(.note(todoID: todo.id, expectedRevision: 5, change: .append(text: "hidden")), as: agent))
        let restoration = try run(.restore(id: todo.id, expectedRevision: 5), as: agent)
        _ = try service.review(proposalID: XCTUnwrap(restoration.proposalID), accept: true, key: "restore", reason: "review", as: .owner)
        let restored = try service.todo(id: todo.id, as: agent)
        XCTAssertEqual(restored.status, .inProgress); XCTAssertEqual(restored.steps[0].isDone, true)
        XCTAssertNil(restored.deletedAt)
    }

    func testMoveChecksBothScopesAndOldGrantLosesReadHistoryProposalAndReplay() throws {
        let project = try service.createProject(name: "project", key: "project", as: .owner)
        let todo = try create(as: agent)
        assertError(.permissionDenied, try run(.update(id: todo.id, expectedRevision: 1, patch: TodoPatch(scope: .project(project.id))), as: agent))
        try grant("codex", [.personal, .project(project.id)])
        let pending = try run(.update(id: todo.id, expectedRevision: 1, patch: TodoPatch(title: "pending")), as: agent, key: "pending")
        let move = try run(.update(id: todo.id, expectedRevision: 1, patch: TodoPatch(scope: .project(project.id))), as: other)
        _ = try service.review(proposalID: XCTUnwrap(move.proposalID), accept: true, key: "move", reason: "review", as: .owner)
        assertError(.permissionDenied, try service.todo(id: todo.id, as: agent))
        assertError(.permissionDenied, try service.todo(id: "unknown", as: agent))
        assertError(.permissionDenied, try service.history(todoID: todo.id, as: agent))
        assertError(.permissionDenied, try service.proposal(id: XCTUnwrap(pending.proposalID), as: agent))
        assertError(.permissionDenied, try run(.update(id: todo.id, expectedRevision: 1, patch: TodoPatch(title: "pending")), as: agent, key: "pending"))
        XCTAssertTrue(try service.listTodos(query: "commitment", as: agent).isEmpty)
        XCTAssertTrue(try service.listProposals(as: agent).isEmpty)
        XCTAssertEqual(try service.todo(id: todo.id, as: other).id, todo.id)
        XCTAssertEqual(try service.history(todoID: todo.id, as: other).count, 2)
    }

    func testRevocationDeniesReceiptsAndStalesApproval() throws {
        let request = CoreOperation.create(title: "persisted", scope: .personal, explicitlyAgreed: true)
        let result = try run(request, as: agent, key: "creation")
        let proposal = try run(.update(id: result.todoIDs[0], expectedRevision: 1, patch: TodoPatch(status: .done)), as: agent)
        _ = try service.revokeIntegration(id: "claude", key: "revoke", as: .owner)
        assertError(.permissionDenied, try run(request, as: agent, key: "creation"))
        assertError(.permissionDenied, try service.listTodos(as: agent))
        assertError(.permissionDenied, try service.listProposals(as: agent))
        XCTAssertEqual(try service.review(proposalID: XCTUnwrap(proposal.proposalID), accept: true, key: "review", reason: "review", as: .owner).outcome, "stale")
        XCTAssertEqual(try service.todo(id: result.todoIDs[0], as: .owner).status, .open)
    }

    func testRestartRecoversStateProposalAndOriginalLostResponseReceipt() throws {
        let operation = CoreOperation.create(title: "durable", scope: .personal, explicitlyAgreed: true)
        let original = try run(operation, as: agent, key: "durable")
        let proposal = try run(.update(id: original.todoIDs[0], expectedRevision: 1, patch: TodoPatch(status: .done)), as: agent)
        service = nil
        service = try CoreService(path: folder.appendingPathComponent("store.sqlite"))
        XCTAssertEqual(try run(operation, as: agent, key: "durable"), original)
        XCTAssertEqual(try service.history(todoID: original.todoIDs[0], as: agent).count, 1)
        XCTAssertEqual(try service.proposal(id: XCTUnwrap(proposal.proposalID), as: agent).state, "pending")
    }

    func testReceiptFailureRollsBackStateEventAndReservedOrder() throws {
        try service.store.execute("CREATE TRIGGER fail_receipt BEFORE INSERT ON operation_receipts WHEN NEW.key='fail' BEGIN SELECT RAISE(ABORT,'injected receipt failure'); END")
        XCTAssertThrowsError(try run(.create(title: "must roll back", scope: .personal, explicitlyAgreed: true), as: agent, key: "fail"))
        XCTAssertTrue(try service.listTodos(as: agent).isEmpty)
        XCTAssertEqual(try service.store.scalarInt("SELECT count(*) FROM change_events WHERE aggregate_type='todo'"), 0)
        XCTAssertEqual(try service.store.scalarInt("SELECT count(*) FROM operation_receipts WHERE actor_id=?", [.text(agent.actorID)]), 0)
        let todo = try create(as: agent)
        XCTAssertEqual(todo.orderKey, 1)
    }

    func testIdenticalTitlesRemainSeparateAndCandidateProposalDoesNotMerge() throws {
        let first = try create("same", as: agent), second = try create("same", as: other)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try service.listTodos(query: "same", as: agent).count, 2)
        let proposal = try service.propose([.create(title: "same", scope: .personal, explicitlyAgreed: false)], candidateIDs: [first.id, second.id], key: "ambiguous", reason: "choose identity", as: agent)
        XCTAssertEqual(try service.proposal(id: XCTUnwrap(proposal.proposalID), as: agent).candidateIDs, [first.id, second.id])
        XCTAssertEqual(try service.listTodos(as: agent).count, 2)
    }

    func testStepOrderExactMembershipAndCrossParentIDRejection() throws {
        let first = try create(), second = try create("other")
        let a = try run(.step(todoID: first.id, expectedRevision: 1, change: .add(title: "a")), as: agent)
        let b = try run(.step(todoID: first.id, expectedRevision: 2, change: .add(title: "b")), as: agent)
        let aID = try XCTUnwrap(a.childID), bID = try XCTUnwrap(b.childID)
        assertError(.invalidInput, try run(.step(todoID: first.id, expectedRevision: 3, change: .reorder(ids: [aID, aID])), as: agent))
        assertError(.notFound, try run(.step(todoID: second.id, expectedRevision: 1, change: .check(id: aID, done: true)), as: agent))
        _ = try run(.step(todoID: first.id, expectedRevision: 3, change: .reorder(ids: [bID, aID])), as: agent)
        XCTAssertEqual(try service.todo(id: first.id, as: agent).steps.map(\.id), [bID, aID])
    }

    func testSameTargetGroupUsesOriginalRevisionAndAppliesSequentialPreview() throws {
        let todo = try create()
        let proposed = try service.propose([
            .update(id: todo.id, expectedRevision: 1, patch: TodoPatch(title: "renamed")),
            .update(id: todo.id, expectedRevision: 1, patch: TodoPatch(status: .done))
        ], key: "two-changes", reason: "one review", as: agent)
        let preview = try service.proposal(id: XCTUnwrap(proposed.proposalID), as: agent)
        XCTAssertEqual(preview.changes[0].after.revision, 2)
        XCTAssertEqual(preview.changes[1].before?.revision, 2)
        XCTAssertEqual(preview.changes[1].after.revision, 3)
        XCTAssertEqual(try service.todo(id: todo.id, as: agent).revision, 1)
        let accepted = try service.review(proposalID: preview.id, accept: true, key: "two-review", reason: "reviewed", as: .owner)
        XCTAssertEqual(accepted.revisions[todo.id], 3)
        let final = try service.todo(id: todo.id, as: agent)
        XCTAssertEqual(final.title, preview.changes[1].after.title)
        XCTAssertEqual(final.status, preview.changes[1].after.status)
        XCTAssertEqual(try service.history(todoID: todo.id, as: agent).count, 3)
    }

    func testTerminalPreviewRetainsFormerScopeProtection() throws {
        let project = try service.createProject(name: "destination", key: "destination", as: .owner)
        try grant("codex", [.personal, .project(project.id)])
        let todo = try create()
        let proposed = try run(.update(id: todo.id, expectedRevision: 1, patch: TodoPatch(scope: .project(project.id))), as: other)
        let id = try XCTUnwrap(proposed.proposalID)
        _ = try service.review(proposalID: id, accept: true, key: "move-review", reason: "reviewed", as: .owner)
        try grant("codex", [.project(project.id)])
        XCTAssertEqual(try service.todo(id: todo.id, as: other).scope, .project(project.id))
        assertError(.permissionDenied, try service.proposal(id: id, as: other))
        XCTAssertTrue(try service.listProposals(as: other).isEmpty)
    }

    func testPermissionDowngradeBlocksWritesButNotScopedReads() throws {
        let todo = try create()
        _ = try service.grantIntegration(id: "claude", credentialRef: "test", scopes: [.personal], canRead: true, canWrite: false, key: "downgrade", as: .owner)
        XCTAssertEqual(try service.todo(id: todo.id, as: agent).id, todo.id)
        assertError(.permissionDenied, try run(.step(todoID: todo.id, expectedRevision: 1, change: .add(title: "forbidden")), as: agent))
        XCTAssertEqual(try service.history(todoID: todo.id, as: agent).count, 1)
    }

    func testTodoAndProjectKeysShareOneActorNamespace() throws {
        _ = try service.createProject(name: "project", key: "shared", as: .owner)
        assertError(.idempotencyMismatch, try run(.create(title: "todo", scope: .personal, explicitlyAgreed: true), key: "shared"))
        _ = try run(.create(title: "todo", scope: .personal, explicitlyAgreed: true), key: "shared2")
        assertError(.idempotencyMismatch, try service.createProject(name: "project", key: "shared2", as: .owner))
    }

    func testRequestCannotForgeReviewProvenance() throws {
        var source = Source(provider: "fixture", session: "session")
        source.proposingActorID = "owner"
        let operation = CoreOperation.create(title: "forged", scope: .personal, explicitlyAgreed: true)
        assertError(.invalidInput, try service.execute(
            MutationRequest(key: "forged-direct", reason: "test", source: source, operation: operation), as: agent))
        assertError(.invalidInput, try service.propose([operation], key: "forged-proposal", reason: "test", source: source, as: agent))
        XCTAssertTrue(try service.listTodos(as: agent).isEmpty)
        XCTAssertTrue(try service.listProposals(as: agent).isEmpty)
    }
}
