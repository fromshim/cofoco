import XCTest
import SQLite3
import Darwin
@testable import CofocoCore

final class ProjectStoreTests: XCTestCase {
    private var fixture: URL!
    private var database: URL { fixture.appendingPathComponent("cofoco.sqlite") }

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appendingPathComponent("cofoco-project-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: fixture)
    }

    func testFolderResolutionUsesCanonicalLongestContainingRoot() throws {
        let db = try SQLiteStore(path: database)
        let projects = ProjectStore(store: db)
        let parent = fixture.appendingPathComponent("repo")
        let child = parent.appendingPathComponent("worktree")
        let nested = child.appendingPathComponent("src")
        let sibling = fixture.appendingPathComponent("repository")
        for directory in [nested, sibling] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let alias = fixture.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parent)
        let a = try projects.create(name: "A", key: "p-a")
        let b = try projects.create(name: "B", key: "p-b")
        _ = try projects.bindFolder(projectID: a.id, expectedRevision: 1, path: parent, key: "bind-a")
        _ = try projects.bindFolder(projectID: b.id, expectedRevision: 1, path: child, key: "bind-b")
        let canonicalParent = try XCTUnwrap(realpath(parent.path, nil))
        defer { free(canonicalParent) }
        XCTAssertEqual(try projects.folderBindings(projectID: a.id, principal: .owner).map(\.canonicalRoot), [String(cString: canonicalParent)])
        XCTAssertThrowsError(try projects.folderBindings(projectID: a.id, principal: .integration("claude"))) { error in
            XCTAssertEqual(error as? CoreError, .permissionDenied)
        }
        XCTAssertEqual(try projects.resolveDirectory(alias, principal: .owner), .project(a.id))
        XCTAssertEqual(try projects.resolveDirectory(nested, principal: .owner), .project(b.id))
        XCTAssertNil(try projects.resolveDirectory(sibling, principal: .owner))
        XCTAssertThrowsError(try projects.bindFolder(projectID: b.id, expectedRevision: 2, path: alias, key: "duplicate-root")) { error in
            XCTAssertEqual(error as? CoreError, .conflict)
        }
    }

    func testGrantIsExplicitAndRevocationImmediatelyHidesProject() throws {
        let db = try SQLiteStore(path: database)
        let projects = ProjectStore(store: db)
        let service = CoreService(store: db)
        let project = try projects.create(name: "Work", key: "create")
        let agent = Principal.integration("claude")
        XCTAssertFalse(try db.authorize(agent, scope: .personal, write: false))
        XCTAssertFalse(try db.authorize(agent, scope: .project(project.id), write: false))
        _ = try projects.grantIntegration(id: "claude", credentialRef: "keychain:claude", scopes: [.project(project.id)], canRead: true, canWrite: true, key: "grant")
        XCTAssertTrue(try service.integrationGrantMatchesCredential(id: "claude", credentialRef: "keychain:claude"))
        XCTAssertFalse(try service.integrationGrantMatchesCredential(id: "claude", credentialRef: "keychain:old"))
        XCTAssertTrue(try db.authorize(agent, scope: .project(project.id), write: true))
        XCTAssertFalse(try db.authorize(agent, scope: .personal, write: false))
        XCTAssertEqual(try projects.projects(principal: agent).map(\.id), [project.id])
        _ = try projects.revokeIntegration(id: "claude", key: "revoke")
        XCTAssertFalse(try service.integrationGrantMatchesCredential(id: "claude", credentialRef: "keychain:claude"))
        XCTAssertFalse(try db.authorize(agent, scope: .project(project.id), write: false))
        XCTAssertNil(try projects.project(id: project.id, principal: agent))
        XCTAssertTrue(try projects.projects(principal: agent).isEmpty)
    }

    func testRemovedDirectoryCanStillBeUnbound() throws {
        let db = try SQLiteStore(path: database)
        let projects = ProjectStore(store: db)
        let folder = fixture.appendingPathComponent("old-root")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let project = try projects.create(name: "Folderless soon", key: "create")
        _ = try projects.bindFolder(projectID: project.id, expectedRevision: 1, path: folder, key: "bind")
        try FileManager.default.removeItem(at: folder)
        let result = try projects.unbindFolder(projectID: project.id, expectedRevision: 2, path: folder, key: "unbind")
        XCTAssertEqual(result.revision, 3)
        XCTAssertTrue(try db.query("SELECT * FROM folder_bindings WHERE project_id=?", [.text(project.id)]).isEmpty)
    }

    func testProjectRetriesNoopsAndStaleRevisionDoNotDuplicateEvents() throws {
        let db = try SQLiteStore(path: database)
        let projects = ProjectStore(store: db)
        let first = try projects.create(name: "Original", key: "create")
        XCTAssertEqual(try projects.create(name: "Original", key: "create"), first)
        XCTAssertThrowsError(try projects.create(name: "Different", key: "create")) { error in
            XCTAssertEqual(error as? CoreError, .idempotencyMismatch)
        }
        let noop = try projects.rename(id: first.id, expectedRevision: 1, name: "Original", key: "same")
        XCTAssertEqual(noop.outcome, .noop)
        let changed = try projects.rename(id: first.id, expectedRevision: 1, name: "Renamed", key: "rename")
        XCTAssertEqual(changed.revision, 2)
        XCTAssertEqual(try projects.rename(id: first.id, expectedRevision: 1, name: "Renamed", key: "rename"), changed)
        XCTAssertThrowsError(try projects.rename(id: first.id, expectedRevision: 1, name: "Stale", key: "stale")) { error in
            XCTAssertEqual(error as? CoreError, .conflict)
        }
        XCTAssertEqual(try db.query("SELECT * FROM change_events WHERE aggregate_id=?", [.text(first.id)]).count, 2)
        XCTAssertEqual(try db.query("SELECT * FROM operation_receipts WHERE actor_id='owner'").count, 3)
    }

    func testSingleOwnerAndUnknownSchemaRefusal() throws {
        var db: SQLiteStore? = try SQLiteStore(path: database)
        XCTAssertThrowsError(try SQLiteStore(path: database)) { error in
            XCTAssertEqual(error as? CoreError, .storeLocked)
        }
        try db?.execute("PRAGMA user_version = 1000")
        db = nil
        XCTAssertThrowsError(try SQLiteStore(path: database)) { error in
            XCTAssertEqual(error as? CoreError, .newerSchema)
        }
    }

    func testTransactionRollsBackStateAndEventTogether() throws {
        let db = try SQLiteStore(path: database)
        XCTAssertThrowsError(try db.transaction { connection in
            try connection.execute("INSERT INTO projects(id,name,revision,created_at,updated_at) VALUES('x','X',1,'now','now')")
            try connection.execute("INSERT INTO change_events(aggregate_type,aggregate_id,actor_id,source,operation,reason,resulting_revision,feedback,created_at) VALUES('project','x','owner','owner','create','test',1,'detail','now')")
            throw CoreError.conflict
        })
        XCTAssertTrue(try db.query("SELECT * FROM projects").isEmpty)
        XCTAssertTrue(try db.query("SELECT * FROM change_events").isEmpty)
    }

    func testUpgradeBacksUpCommittedWalStateBeforeMigration() throws {
        var original: SQLiteStore? = try SQLiteStore(path: database)
        let project = try ProjectStore(store: original!).create(name: "Durable", key: "create")
        try original?.execute("DROP TABLE notification_deliveries")
        try original?.execute("PRAGMA user_version = 1")
        original = nil

        let upgraded = try SQLiteStore(path: database)
        XCTAssertEqual(try upgraded.query("PRAGMA user_version").first?.int64("user_version"), 2)
        XCTAssertNotNil(upgraded.preMigrationBackup)
        XCTAssertEqual(try upgraded.query("SELECT name FROM projects WHERE id=?", [.text(project.id)]).first?.string("name"), "Durable")
        XCTAssertEqual(try upgraded.query("SELECT name FROM sqlite_master WHERE name='notification_deliveries'").count, 1)

        let backup = try XCTUnwrap(upgraded.preMigrationBackup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), backup.path)
        let restoredPath = fixture.appendingPathComponent("restored.sqlite")
        try FileManager.default.copyItem(at: backup, to: restoredPath)
        let restored = try SQLiteStore(path: restoredPath)
        XCTAssertEqual(try restored.query("SELECT name FROM projects WHERE id=?", [.text(project.id)]).first?.string("name"), "Durable")
        XCTAssertEqual(try restored.query("PRAGMA user_version").first?.int64("user_version"), 2)
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(backup.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard opened == SQLITE_OK else {
            XCTFail("Backup could not open at \(backup.path), SQLite code \(opened)")
            if let handle { sqlite3_close(handle) }
            return
        }
        defer { if let handle { sqlite3_close(handle) } }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, "SELECT name FROM projects WHERE id=?", -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            XCTFail("Backup query failed, SQLite code \(prepared)")
            return
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        XCTAssertEqual(project.id.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }, SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "Durable")
    }
}
