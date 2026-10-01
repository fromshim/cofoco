import Foundation
import Darwin

public struct ProjectMutationResult: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case created, updated, removed, noop }
    public let outcome: Outcome
    public let id: String
    public let revision: Int64
}

/// Project settings use the same connection and transaction boundary as Todo writes.
final class ProjectStore {
    let store: SQLiteStore

    init(store: SQLiteStore) { self.store = store }

    func create(name: String, key: String, principal: Principal = .owner) throws -> ProjectMutationResult {
        try owner(principal)
        let clean = try validName(name)
        return try mutate(key: key, fingerprint: ["create", clean]) { db in
            let id = UUID().uuidString.lowercased()
            let now = timestamp()
            try db.execute("INSERT INTO projects(id,name,revision,created_at,updated_at) VALUES(?,?,1,?,?)",
                           [.text(id), .text(clean), .text(now), .text(now)])
            try event(db, id: id, operation: "project_created", before: nil, after: clean, revision: 1)
            return ProjectMutationResult(outcome: .created, id: id, revision: 1)
        }
    }

    func rename(id: String, expectedRevision: Int64, name: String, key: String, principal: Principal = .owner) throws -> ProjectMutationResult {
        try owner(principal)
        let clean = try validName(name)
        return try mutate(key: key, fingerprint: ["rename", id, String(expectedRevision), clean]) { db in
            let project = try requireProject(db, id: id)
            guard project.revision == expectedRevision else { throw CoreError.conflict }
            guard project.name != clean else { return .init(outcome: .noop, id: id, revision: project.revision) }
            let revision = project.revision + 1
            try db.execute("UPDATE projects SET name=?, revision=?, updated_at=? WHERE id=?",
                           [.text(clean), .integer(revision), .text(timestamp()), .text(id)])
            try event(db, id: id, operation: "project_renamed", before: project.name, after: clean, revision: revision)
            return .init(outcome: .updated, id: id, revision: revision)
        }
    }

    func bindFolder(projectID: String, expectedRevision: Int64, path: URL, key: String, principal: Principal = .owner) throws -> ProjectMutationResult {
        try owner(principal)
        let root = try canonicalDirectory(path)
        return try mutate(key: key, fingerprint: ["bind", projectID, String(expectedRevision), root]) { db in
            let project = try requireProject(db, id: projectID)
            guard project.revision == expectedRevision else { throw CoreError.conflict }
            if let existing = try db.query("SELECT project_id FROM folder_bindings WHERE canonical_root=?", [.text(root)]).first {
                guard existing.string("project_id") == projectID else { throw CoreError.conflict }
                return .init(outcome: .noop, id: projectID, revision: project.revision)
            }
            let revision = project.revision + 1
            try db.execute("INSERT INTO folder_bindings(canonical_root,project_id,created_at) VALUES(?,?,?)",
                           [.text(root), .text(projectID), .text(timestamp())])
            try db.execute("UPDATE projects SET revision=?,updated_at=? WHERE id=?",
                           [.integer(revision), .text(timestamp()), .text(projectID)])
            try event(db, id: projectID, operation: "folder_bound", before: nil, after: root, revision: revision)
            return .init(outcome: .updated, id: projectID, revision: revision)
        }
    }

    func unbindFolder(projectID: String, expectedRevision: Int64, path: URL, key: String, principal: Principal = .owner) throws -> ProjectMutationResult {
        try owner(principal)
        let root = try canonicalBindingPath(path)
        return try mutate(key: key, fingerprint: ["unbind", projectID, String(expectedRevision), root]) { db in
            let project = try requireProject(db, id: projectID)
            guard project.revision == expectedRevision else { throw CoreError.conflict }
            guard let binding = try db.query("SELECT project_id FROM folder_bindings WHERE canonical_root=?", [.text(root)]).first,
                  binding.string("project_id") == projectID else {
                return .init(outcome: .noop, id: projectID, revision: project.revision)
            }
            let revision = project.revision + 1
            try db.execute("DELETE FROM folder_bindings WHERE canonical_root=?", [.text(root)])
            try db.execute("UPDATE projects SET revision=?,updated_at=? WHERE id=?",
                           [.integer(revision), .text(timestamp()), .text(projectID)])
            try event(db, id: projectID, operation: "folder_unbound", before: root, after: nil, revision: revision)
            return .init(outcome: .removed, id: projectID, revision: revision)
        }
    }

    func project(id: String, principal: Principal) throws -> Project? {
        try store.transaction { db in
            guard try db.authorize(principal, scope: .project(id), write: false) else { return nil }
            return try db.query("SELECT * FROM projects WHERE id=?", [.text(id)]).first.map(projectFromRow)
        }
    }

    func projects(principal: Principal) throws -> [Project] {
        try store.transaction { db in
            let all = try db.query("SELECT * FROM projects ORDER BY name,id").map(projectFromRow)
            return try all.filter { try db.authorize(principal, scope: .project($0.id), write: false) }
        }
    }

    /// Folder paths are settings data, not an integration-facing context listing.
    func folderBindings(projectID: String, principal: Principal) throws -> [FolderBinding] {
        try owner(principal)
        return try store.transaction { db in
            _ = try requireProject(db, id: projectID)
            return try db.query("SELECT * FROM folder_bindings WHERE project_id=? ORDER BY canonical_root", [.text(projectID)]).map { row in
                FolderBinding(projectID: row.string("project_id"), canonicalRoot: row.string("canonical_root"), createdAt: row.string("created_at"))
            }
        }
    }

    /// Returns no project when a root is unknown or the current grant cannot read it.
    func resolveDirectory(_ url: URL, principal: Principal) throws -> Scope? {
        let path = try canonicalDirectory(url)
        return try store.transaction { db in
            let roots = try db.query("SELECT canonical_root,project_id FROM folder_bindings")
            let match = roots.filter { row in
                let root = row.string("canonical_root")
                return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
            }.max { $0.string("canonical_root").count < $1.string("canonical_root").count }
            guard let match else { return nil }
            let scope = Scope.project(match.string("project_id"))
            return try db.authorize(principal, scope: scope, write: false) ? scope : nil
        }
    }

    func grantIntegration(id: String, credentialRef: String, scopes: [Scope], canRead: Bool, canWrite: Bool, key: String, principal: Principal = .owner) throws -> ProjectMutationResult {
        try owner(principal)
        guard !id.isEmpty, !credentialRef.isEmpty, canRead || !canWrite else { throw CoreError.invalidInput }
        let keys = Array(Set(scopes.map(\.key))).sorted()
        guard !keys.isEmpty else { throw CoreError.invalidInput }
        return try mutate(key: key, fingerprint: ["grant", id, credentialRef, canRead.description, canWrite.description] + keys) { db in
            for scope in scopes {
                if case .project(let projectID) = scope { _ = try requireProject(db, id: projectID) }
            }
            let prior = try db.query("SELECT credential_ref,can_read,can_write,revoked_at FROM integration_grants WHERE integration_id=?", [.text(id)]).first
            let oldKeys = try db.query("SELECT scope_key FROM grant_scopes WHERE integration_id=? ORDER BY scope_key", [.text(id)]).map { $0.string("scope_key") }
            let unchanged = prior?.string("credential_ref") == credentialRef && prior?.bool("can_read") == canRead && prior?.bool("can_write") == canWrite && prior?.optionalString("revoked_at") == nil && oldKeys == keys
            if unchanged { return .init(outcome: .noop, id: id, revision: 1) }
            let now = timestamp()
            try db.execute("""
                INSERT INTO integration_grants(integration_id,credential_ref,can_read,can_write,revoked_at,created_at,updated_at)
                VALUES(?,?,?,?,NULL,?,?)
                ON CONFLICT(integration_id) DO UPDATE SET credential_ref=excluded.credential_ref,
                can_read=excluded.can_read,can_write=excluded.can_write,revoked_at=NULL,updated_at=excluded.updated_at
                """, [.text(id), .text(credentialRef), .integer(canRead ? 1 : 0), .integer(canWrite ? 1 : 0), .text(now), .text(now)])
            try db.execute("DELETE FROM grant_scopes WHERE integration_id=?", [.text(id)])
            for scopeKey in keys {
                try db.execute("INSERT INTO grant_scopes(integration_id,scope_key) VALUES(?,?)", [.text(id), .text(scopeKey)])
            }
            try event(db, id: id, operation: "grant_changed", before: nil, after: keys.joined(separator: ","), revision: 1, aggregateType: "grant")
            return .init(outcome: prior == nil ? .created : .updated, id: id, revision: 1)
        }
    }

    func revokeIntegration(id: String, key: String, principal: Principal = .owner) throws -> ProjectMutationResult {
        try owner(principal)
        guard !id.isEmpty else { throw CoreError.invalidInput }
        return try mutate(key: key, fingerprint: ["revoke", id]) { db in
            guard let row = try db.query("SELECT revoked_at FROM integration_grants WHERE integration_id=?", [.text(id)]).first else { throw CoreError.notFound }
            guard row.optionalString("revoked_at") == nil else { return .init(outcome: .noop, id: id, revision: 1) }
            try db.execute("UPDATE integration_grants SET revoked_at=?,updated_at=? WHERE integration_id=?",
                           [.text(timestamp()), .text(timestamp()), .text(id)])
            try event(db, id: id, operation: "grant_revoked", before: nil, after: nil, revision: 1, aggregateType: "grant")
            return .init(outcome: .removed, id: id, revision: 1)
        }
    }

    private func mutate(key: String, fingerprint parts: [String], body: (SQLiteStore) throws -> ProjectMutationResult) throws -> ProjectMutationResult {
        guard !key.isEmpty else { throw CoreError.invalidInput }
        let fingerprint = parts.map { "\($0.utf8.count):\($0)" }.joined()
        return try store.transaction { db in
            if let existing = try db.query("SELECT fingerprint,result_json FROM operation_receipts WHERE actor_id='owner' AND key=?", [.text(key)]).first {
                guard existing.string("fingerprint") == fingerprint else { throw CoreError.idempotencyMismatch }
                guard let data = existing.string("result_json").data(using: .utf8) else { throw CoreError.storage("Invalid receipt") }
                return try JSONDecoder().decode(ProjectMutationResult.self, from: data)
            }
            let result = try body(db)
            let json = String(data: try JSONEncoder().encode(result), encoding: .utf8)!
            try db.execute("INSERT INTO operation_receipts(actor_id,key,fingerprint,result_json,access_json,created_at) VALUES('owner',?,?,?,?,?)",
                           [.text(key), .text(fingerprint), .text(json), .text("[]"), .text(timestamp())])
            return result
        }
    }

    private func event(_ db: SQLiteStore, id: String, operation: String, before: String?, after: String?, revision: Int64, aggregateType: String = "project") throws {
        let beforeJSON = try before.map { String(data: try JSONEncoder().encode($0), encoding: .utf8)! }
        let afterJSON = try after.map { String(data: try JSONEncoder().encode($0), encoding: .utf8)! }
        try db.execute("""
            INSERT INTO change_events(aggregate_type,aggregate_id,actor_id,source,operation,before_json,after_json,reason,resulting_revision,feedback,created_at)
            VALUES(? ,?,'owner','{}',?,?,?,?,?,'detail',?)
            """, [.text(aggregateType), .text(id), .text(operation), beforeJSON.map(SQLValue.text) ?? .null, afterJSON.map(SQLValue.text) ?? .null,
                  .text("Project settings"), .integer(revision), .text(timestamp())])
    }

    private func projectFromRow(_ row: SQLRow) -> Project {
        Project(id: row.string("id"), name: row.string("name"), revision: row.int64("revision"),
                createdAt: row.string("created_at"), updatedAt: row.string("updated_at"))
    }

    private func requireProject(_ db: SQLiteStore, id: String) throws -> Project {
        guard let row = try db.query("SELECT * FROM projects WHERE id=?", [.text(id)]).first else { throw CoreError.notFound }
        return projectFromRow(row)
    }

    private func owner(_ principal: Principal) throws {
        guard store.isOwner(principal) else { throw CoreError.permissionDenied }
    }

    private func validName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200 else { throw CoreError.invalidInput }
        return name
    }

    private func canonicalDirectory(_ url: URL) throws -> String {
        guard url.isFileURL else { throw CoreError.invalidInput }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let resolved = realpath(url.path, nil) else { throw CoreError.invalidInput }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// A recorded root must remain removable after its directory was moved or deleted.
    private func canonicalBindingPath(_ url: URL) throws -> String {
        guard url.isFileURL else { throw CoreError.invalidInput }
        if FileManager.default.fileExists(atPath: url.path) { return try canonicalDirectory(url) }
        var ancestor = url.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path) {
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { throw CoreError.invalidInput }
            missing.append(ancestor.lastPathComponent)
            ancestor = parent
        }
        var canonical = try canonicalDirectory(ancestor)
        for component in missing.reversed() {
            canonical = URL(fileURLWithPath: canonical).appendingPathComponent(component).path
        }
        return canonical
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
