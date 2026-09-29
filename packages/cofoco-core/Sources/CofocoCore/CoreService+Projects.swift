import Foundation

public extension CoreService {
    func createProject(name: String, key: String, as principal: Principal) throws -> ProjectMutationResult {
        try ProjectStore(store: store).create(name: name, key: key, principal: principal)
    }

    func renameProject(id: String, expectedRevision: Int64, name: String, key: String, as principal: Principal) throws -> ProjectMutationResult {
        try ProjectStore(store: store).rename(id: id, expectedRevision: expectedRevision, name: name, key: key, principal: principal)
    }

    func bindProjectFolder(projectID: String, expectedRevision: Int64, path: URL, key: String, as principal: Principal) throws -> ProjectMutationResult {
        try ProjectStore(store: store).bindFolder(projectID: projectID, expectedRevision: expectedRevision, path: path, key: key, principal: principal)
    }

    func unbindProjectFolder(projectID: String, expectedRevision: Int64, path: URL, key: String, as principal: Principal) throws -> ProjectMutationResult {
        try ProjectStore(store: store).unbindFolder(projectID: projectID, expectedRevision: expectedRevision, path: path, key: key, principal: principal)
    }

    func getProject(id: String, as principal: Principal) throws -> Project? {
        try ProjectStore(store: store).project(id: id, principal: principal)
    }

    func listProjects(as principal: Principal) throws -> [Project] {
        try ProjectStore(store: store).projects(principal: principal)
    }

    func listProjectFolders(projectID: String, as principal: Principal) throws -> [FolderBinding] {
        try ProjectStore(store: store).folderBindings(projectID: projectID, principal: principal)
    }

    func resolveProjectFolder(_ path: URL, as principal: Principal) throws -> Scope? {
        try ProjectStore(store: store).resolveDirectory(path, principal: principal)
    }

    func grantIntegration(id: String, credentialRef: String, scopes: [Scope], canRead: Bool, canWrite: Bool, key: String, as principal: Principal) throws -> ProjectMutationResult {
        try ProjectStore(store: store).grantIntegration(id: id, credentialRef: credentialRef, scopes: scopes, canRead: canRead, canWrite: canWrite, key: key, principal: principal)
    }

    func revokeIntegration(id: String, key: String, as principal: Principal) throws -> ProjectMutationResult {
        try ProjectStore(store: store).revokeIntegration(id: id, key: key, principal: principal)
    }

    /// A transport may bind an authenticated credential to a currently active grant.
    /// This never returns grant details and does not replace per-operation scope checks.
    func integrationGrantMatchesCredential(id: String, credentialRef: String) throws -> Bool {
        try store.transaction { db in
            guard !id.isEmpty, !credentialRef.isEmpty,
                  let row = try db.query("SELECT credential_ref FROM integration_grants WHERE integration_id=? AND revoked_at IS NULL AND can_read=1",
                                         [.text(id)]).first else { return false }
            return row.string("credential_ref") == credentialRef
        }
    }
}
