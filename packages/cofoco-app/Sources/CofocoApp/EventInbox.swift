import Foundation

struct EventInbox: Codable {
    var cursor: Int64
    var alerts: [AppEvent]

    static var location: URL { AppPaths.root.appendingPathComponent("event-inbox.json") }

    static func load(from location: URL = Self.location) -> EventInbox? {
        guard let data = try? Data(contentsOf: location) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save(to location: URL = Self.location) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: location, options: .atomic)
    }
}
