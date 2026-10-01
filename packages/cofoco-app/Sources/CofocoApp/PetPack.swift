import AppKit
import Foundation
import SwiftUI

enum PetPose: String, CaseIterable, Codable, Sendable {
    case idle, working, noticed, resting

    var label: String {
        switch self {
        case .idle: "기본"
        case .working: "진행 중"
        case .noticed: "알림"
        case .resting: "쉬는 중"
        }
    }
}

struct PetPack: Codable, Equatable, Sendable {
    var frames: [PetPose: [String]] = [:]

    static var root: URL {
        AppPaths.root.appendingPathComponent("Pets", isDirectory: true)
    }

    static var manifest: URL { root.appendingPathComponent("pack.json") }

    static func load(from manifest: URL = Self.manifest) -> PetPack {
        guard let data = try? Data(contentsOf: manifest),
              let pack = try? JSONDecoder().decode(PetPack.self, from: data) else { return PetPack() }
        return pack
    }

    func save(to manifest: URL = Self.manifest) throws {
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: manifest, options: .atomic)
    }

    func importing(_ urls: [URL], for pose: PetPose, destination: URL = Self.root) throws -> PetPack {
        guard !urls.isEmpty else { throw PetImportError.empty }
        guard pose == .idle || !(frames[.idle] ?? []).isEmpty else { throw PetImportError.idleRequired }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for url in urls {
            guard ["png", "webp"].contains(url.pathExtension.lowercased()) else { throw PetImportError.unsupported }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard NSImage(contentsOf: url) != nil else { throw PetImportError.invalidImage }
        }
        var stored: [String] = []
        for url in urls {
            let extensionName = url.pathExtension.lowercased()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let name = UUID().uuidString + "." + extensionName
            try FileManager.default.copyItem(at: url, to: destination.appendingPathComponent(name))
            stored.append(name)
        }
        var copy = self
        copy.frames[pose] = stored
        return copy
    }

    func urls(for pose: PetPose, directory: URL = Self.root) -> [URL] {
        let names = frames[pose].flatMap { $0.isEmpty ? nil : $0 } ?? frames[.idle] ?? []
        return names.map { directory.appendingPathComponent($0) }
    }

    func motion(for pose: PetPose) -> PetPose {
        (frames[pose] ?? []).isEmpty ? .idle : pose
    }
}

enum PetImportError: LocalizedError {
    case empty, unsupported, invalidImage, idleRequired
    var errorDescription: String? {
        switch self {
        case .empty: "이미지를 하나 이상 골라주세요."
        case .unsupported: "PNG 또는 WebP 이미지만 가져올 수 있어요."
        case .invalidImage: "이미지를 열 수 없어요. 다른 파일을 선택해 주세요."
        case .idleRequired: "기본 이미지를 먼저 가져와 주세요."
        }
    }
}

enum PetMotion {
    static func frameIndex(pose: PetPose, count: Int, elapsed: TimeInterval, reduceMotion: Bool) -> Int {
        guard count > 1, !reduceMotion else { return 0 }
        switch pose {
        case .idle, .resting:
            let time = elapsed.truncatingRemainder(dividingBy: 6)
            return time >= 0.45 && time < 1.15 ? 1 : 0
        case .noticed, .working:
            guard count > 2 else {
                let time = elapsed.truncatingRemainder(dividingBy: 6)
                return time < 0.7 ? 1 : 0
            }
            let interval = pose == .noticed ? 0.32 : 0.16
            let actionDuration = interval * 4 * 4
            let time = elapsed.truncatingRemainder(dividingBy: actionDuration + 4)
            guard time < actionDuration else { return 0 }
            let sequence = pose == .noticed ? [0, 1, 2, 1] : [0, 1, 0, 2]
            return sequence[Int(time / interval) % sequence.count]
        }
    }
}

@MainActor private enum PetImageCache {
    static let images = NSCache<NSString, NSImage>()
    static func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}

struct PetArtwork: View {
    let pack: PetPack
    let pose: PetPose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let urls = pack.urls(for: pose)
        Group {
            if urls.isEmpty {
                OriginalPet(pose: pose)
            } else if reduceMotion || urls.count == 1 {
                petImage(urls[0])
            } else {
                TimelineView(.periodic(from: .now, by: 0.16)) { timeline in
                    let index = PetMotion.frameIndex(pose: pack.motion(for: pose), count: urls.count,
                                                     elapsed: timeline.date.timeIntervalSince1970,
                                                     reduceMotion: reduceMotion)
                    petImage(urls[index])
                }
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityLabel("Cofoco 펫, \(pose.label)")
    }

    @ViewBuilder private func petImage(_ url: URL) -> some View {
        if let image = PetImageCache.image(at: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
        } else { OriginalPet(pose: pose) }
    }
}

/// Original code-drawn default: a small pebble companion, not a third-party character asset.
private struct OriginalPet: View {
    let pose: PetPose
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Ellipse()
                .fill(colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor))
                .frame(width: 100, height: pose == .resting ? 65 : 85)
                .overlay {
                    Ellipse().strokeBorder(Color.primary.opacity(0.55), lineWidth: 2)
                }
                .offset(y: pose == .resting ? 19 : 10)
            HStack(spacing: 27) {
                Capsule().fill(Color.primary).frame(width: 4, height: pose == .resting ? 3 : 7)
                Capsule().fill(Color.primary).frame(width: 4, height: pose == .resting ? 3 : 7)
            }
            .offset(y: pose == .resting ? 13 : 0)
            Capsule().fill(Color.primary.opacity(0.8)).frame(width: 9, height: 2).offset(y: 20)
            if pose != .resting {
                HStack(spacing: 47) {
                    Ellipse().fill(Color.primary.opacity(0.35)).frame(width: 13, height: 9)
                    Ellipse().fill(Color.primary.opacity(0.35)).frame(width: 13, height: 9)
                }.offset(y: 12)
            }
        }
        .frame(width: 112, height: 112)
    }
}
