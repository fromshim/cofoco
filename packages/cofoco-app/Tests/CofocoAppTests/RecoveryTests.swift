import AppKit
import XCTest
@testable import CofocoApp

final class RecoveryTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cofoco-app-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testEventInboxRecoversCursorAndUnreadQueueTogether() throws {
        let location = try temporaryRoot().appendingPathComponent("inbox.json")
        let event = AppEvent(cursor: 41, aggregateId: "todo-1", actorId: "integration:claude", operation: "create",
                             reason: "agreed commitment", feedback: "todo", resultingRevision: 1, provider: "claude")
        try EventInbox(cursor: 42, alerts: [event]).save(to: location)
        let restored = try XCTUnwrap(EventInbox.load(from: location))
        XCTAssertEqual(restored.cursor, 42)
        XCTAssertEqual(restored.alerts.map(\.cursor), [41])
        try EventInbox(cursor: 42, alerts: []).save(to: location)
        XCTAssertTrue(try XCTUnwrap(EventInbox.load(from: location)).alerts.isEmpty)
    }

    func testInvalidInboxDoesNotPretendToHaveAValidCursor() throws {
        let location = try temporaryRoot().appendingPathComponent("inbox.json")
        try Data("invalid".utf8).write(to: location)
        XCTAssertNil(EventInbox.load(from: location))
    }

    func testPetImportCopiesLocallyAndSurvivesSourceRemoval() throws {
        let root = try temporaryRoot()
        let source = root.appendingPathComponent("source.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: source)
        let storage = root.appendingPathComponent("Pets")
        let pack = try PetPack().importing([source], for: .idle, destination: storage)
        let manifest = storage.appendingPathComponent("pack.json")
        try pack.save(to: manifest)
        try FileManager.default.removeItem(at: source)
        let restored = PetPack.load(from: manifest)
        XCTAssertEqual(restored, pack)
        for pose in PetPose.allCases {
            let urls = restored.urls(for: pose, directory: storage)
            XCTAssertEqual(urls.count, 1)
            XCTAssertNotNil(NSImage(contentsOf: urls[0]))
            XCTAssertEqual(restored.motion(for: pose), .idle)
        }
    }

    func testPetRequiresIdleAndValidatesWholeSelectionBeforeCopy() throws {
        let root = try temporaryRoot()
        XCTAssertThrowsError(try PetPack().importing([root.appendingPathComponent("missing.png")], for: .working, destination: root))
        let invalid = root.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        XCTAssertThrowsError(try PetPack().importing([invalid], for: .idle, destination: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["invalid.png"])
    }

    func testDotsRiseInSequenceThenRemainStillForLongRest() {
        XCTAssertLessThan(DotMotion.offset(index: 0, elapsed: 0.15), 0)
        XCTAssertEqual(DotMotion.offset(index: 1, elapsed: 0.15), 0)
        XCTAssertLessThan(DotMotion.offset(index: 2, elapsed: 0.5), 0)
        for index in 0..<3 { XCTAssertEqual(DotMotion.offset(index: index, elapsed: 2), 0) }
    }

    func testPendingMutationRetainsExactPayloadAndKeyAcrossRestart() throws {
        let location = try temporaryRoot().appendingPathComponent("pending.json")
        let body: [String: Any] = ["idempotency_key": "one-action", "title": "영양제 사기", "expected_revision": 3]
        let mutation = try PendingMutation(method: "PATCH", path: "/v1/owner/todos/one", body: body)
        try mutation.save(to: location)
        let restored = try XCTUnwrap(PendingMutation.load(from: location))
        XCTAssertEqual(restored.method, "PATCH")
        XCTAssertEqual(restored.path, mutation.path)
        XCTAssertEqual(restored.body, mutation.body)
        XCTAssertEqual(try restored.object["idempotency_key"] as? String, "one-action")
        try PendingMutation.clear(at: location)
        XCTAssertNil(try PendingMutation.load(from: location))
    }

    func testPanelDoesNotInterceptTransparentGutterOrPetGap() {
        func hit(_ point: CGPoint) -> Bool {
            PanelHitRegions.contains(point, width: 350, height: 545, bubbleVisible: true, mainHeight: 405, changeHeight: nil)
        }
        XCTAssertFalse(hit(CGPoint(x: 5, y: 400)))
        XCTAssertFalse(hit(CGPoint(x: 100, y: 60)))
        XCTAssertFalse(hit(CGPoint(x: 280, y: 125)))
        XCTAssertTrue(hit(CGPoint(x: 280, y: 60)))
        XCTAssertTrue(hit(CGPoint(x: 100, y: 200)))
    }
}
