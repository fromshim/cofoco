import Foundation

/// Retains the exact key/payload across a lost HTTP response and app restart.
/// Contains local Todo data, never the Keychain bearer credential.
struct PendingMutation: Codable, Equatable {
    let method: String
    let path: String
    let body: Data
    static var location: URL { AppPaths.root.appendingPathComponent("pending-mutation.json") }

    init(method: String, path: String, body: [String: Any]) throws {
        self.method = method
        self.path = path
        self.body = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
    }

    var object: [String: Any] {
        get throws { try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:] }
    }

    static func load(from location: URL = Self.location) throws -> PendingMutation? {
        guard FileManager.default.fileExists(atPath: location.path) else { return nil }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: location))
    }

    func save(to location: URL = Self.location) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: location, options: .atomic)
    }

    static func clear(at location: URL = Self.location) throws {
        if FileManager.default.fileExists(atPath: location.path) { try FileManager.default.removeItem(at: location) }
    }
}
