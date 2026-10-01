import Foundation

enum AppPaths {
    static var root: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["COFOCO_DATA_ROOT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cofoco", isDirectory: true)
    }

    static var preferences: UserDefaults {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["COFOCO_PREFERENCES_SUITE"], let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        #endif
        return .standard
    }
}
