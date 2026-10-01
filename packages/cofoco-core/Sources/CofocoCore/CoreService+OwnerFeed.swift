import Foundation

public struct IntegrationSummary: Codable, Equatable, Sendable {
    public let id: String
    public let scopes: [String]
    public let canRead: Bool
    public let canWrite: Bool
    public let revoked: Bool
}

public extension CoreService {
    /// The desktop owner uses a durable cursor and refreshes its snapshot on launch/reconnect.
    /// Integration callers intentionally cannot inspect the unfiltered owner feed.
    func ownerEvents(after cursor: Int64, limit: Int = 100, as principal: Principal) throws -> [ChangeEvent] {
        try store.transaction { db in
            guard db.isOwner(principal) else { throw CoreError.permissionDenied }
            guard cursor >= 0, (1...200).contains(limit) else { throw CoreError.invalidInput }
            return try db.query("SELECT * FROM change_events WHERE cursor>? ORDER BY cursor LIMIT ?",
                                [.integer(cursor), .integer(Int64(limit))]).map(event)
        }
    }

    func latestOwnerEventCursor(as principal: Principal) throws -> Int64 {
        try store.transaction { db in
            guard db.isOwner(principal) else { throw CoreError.permissionDenied }
            return try db.scalarInt("SELECT COALESCE(MAX(cursor),0) FROM change_events") ?? 0
        }
    }

    func ownerIntegrations(as principal: Principal) throws -> [IntegrationSummary] {
        try store.transaction { db in
            guard db.isOwner(principal) else { throw CoreError.permissionDenied }
            return try db.query("SELECT integration_id,can_read,can_write,revoked_at FROM integration_grants ORDER BY integration_id").map { row in
                let id = row.string("integration_id")
                let scopes = try db.query("SELECT scope_key FROM grant_scopes WHERE integration_id=? ORDER BY scope_key",
                                          [.text(id)]).map { $0.string("scope_key") }
                return IntegrationSummary(id: id, scopes: scopes, canRead: row.bool("can_read"),
                                          canWrite: row.bool("can_write"), revoked: row.optionalString("revoked_at") != nil)
            }
        }
    }
}
