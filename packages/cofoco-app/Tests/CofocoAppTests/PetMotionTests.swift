import XCTest
@testable import CofocoApp

final class PetMotionTests: XCTestCase {
    func testMotionUsesStillFrameWhenReducedOrOneFrame() {
        XCTAssertEqual(PetMotion.frameIndex(pose: .working, count: 3, elapsed: 0.32, reduceMotion: true), 0)
        XCTAssertEqual(PetMotion.frameIndex(pose: .noticed, count: 1, elapsed: 0.32, reduceMotion: false), 0)
    }

    func testWorkingDanceHasLongRestAndFourFrameSequence() {
        XCTAssertEqual(PetMotion.frameIndex(pose: .working, count: 3, elapsed: 0, reduceMotion: false), 0)
        XCTAssertEqual(PetMotion.frameIndex(pose: .working, count: 3, elapsed: 0.17, reduceMotion: false), 1)
        XCTAssertEqual(PetMotion.frameIndex(pose: .working, count: 3, elapsed: 0.33, reduceMotion: false), 0)
        XCTAssertEqual(PetMotion.frameIndex(pose: .working, count: 3, elapsed: 0.49, reduceMotion: false), 2)
        XCTAssertEqual(PetMotion.frameIndex(pose: .working, count: 3, elapsed: 3, reduceMotion: false), 0)
    }

    func testIdleBlinkIsQuietBetweenActions() {
        XCTAssertEqual(PetMotion.frameIndex(pose: .idle, count: 2, elapsed: 0.5, reduceMotion: false), 1)
        XCTAssertEqual(PetMotion.frameIndex(pose: .idle, count: 2, elapsed: 2, reduceMotion: false), 0)
    }
}
