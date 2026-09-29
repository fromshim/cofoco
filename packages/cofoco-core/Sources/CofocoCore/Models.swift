import Foundation

public enum Principal: Hashable, Sendable {
    case owner
    case integration(String)

    public var actorID: String {
        switch self {
        case .owner: "owner"
        case .integration(let id): "integration:\(id)"
        }
    }
}

public enum Scope: Hashable, Codable, Sendable {
    case personal
    case project(String)

    public var key: String {
        switch self {
        case .personal: "personal"
        case .project(let id): "project:\(id)"
        }
    }

    public var projectID: String? {
        if case .project(let id) = self { return id }
        return nil
    }
}

public enum TodoStatus: String, Codable, Sendable {
    case open
    case inProgress = "in_progress"
    case done
}

public enum StatusAuthority: String, Codable, Sendable {
    case `default`
    case agent
    case owner
}

public struct Project: Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    public let revision: Int64
    public let createdAt: String
    public let updatedAt: String
}

public struct FolderBinding: Equatable, Codable, Sendable {
    public let projectID: String
    public let canonicalRoot: String
    public let createdAt: String
}

public enum CoreError: Error, Equatable, Sendable {
    case invalidInput
    case permissionDenied
    case unresolvedScope
    case notFound
    case conflict
    case idempotencyMismatch
    case parentClosed
    case parentDeleted
    case newerSchema
    case storeLocked
    case storage(String)
}
