import XCTest
@testable import ShowbackCore

final class PresentationTests: XCTestCase {
    func testPointerImageCacheReusesSettledFramesAndInvalidatesMovement() throws {
        var timeline = PointerTimeline()
        try timeline.point(at: 1, target: Box(x: 100, y: 100, width: 50, height: 30),
                           viewport: Box(x: 0, y: 0, width: 800, height: 600))
        let cache = PointerImageCache(timeline: timeline, size: CGSize(width: 800, height: 600))
        XCTAssertNil(cache.image(at: 0))
        let moving = try XCTUnwrap(cache.image(at: 1.1))
        let settled = try XCTUnwrap(cache.image(at: 2))
        XCTAssertFalse(moving === settled)
        XCTAssertTrue(settled === cache.image(at: 3))
    }

    func testReducedMotionPlacesPointerWithoutTravel() throws {
        var timeline = PointerTimeline()
        try timeline.point(at: 1, target: Box(x: 100, y: 100, width: 200, height: 40),
                           viewport: Box(x: 0, y: 0, width: 800, height: 600), travel: 0)
        let frame = try XCTUnwrap(timeline.frame(at: 1, width: 1600, height: 1200))
        XCTAssertEqual(frame.x, 400, accuracy: 0.001)
        XCTAssertEqual(frame.y, 240, accuracy: 0.001)
    }
    func testCaptureUsesActualPixelScaleWithoutEmptyCanvas() throws {
        let box = Box(x: -1200, y: 100, width: 760, height: 540)
        XCTAssertEqual(try captureDimensions(viewport: box, pixelScale: 1), CGSize(width: 760, height: 540))
        XCTAssertEqual(try captureDimensions(viewport: box, pixelScale: 2), CGSize(width: 1520, height: 1080))
    }
    func testNegativeDisplayOriginAndRetinaScaleUseSameTarget() throws {
        let viewport = Box(x: -1200, y: 100, width: 800, height: 600)
        let target = Box(x: -1100, y: 200, width: 200, height: 40)
        var timeline = PointerTimeline()
        try timeline.point(at: 1, target: target, viewport: viewport)
        let frame = try XCTUnwrap(timeline.frame(at: 2, width: 1600, height: 1200))
        XCTAssertEqual(frame.x, 400, accuracy: 0.001)
        XCTAssertEqual(frame.y, 240, accuracy: 0.001)
        XCTAssertNil(timeline.frame(at: 0, width: 1600, height: 1200))
    }
    func testRefusesTargetOutsideSelectedWindow() {
        var timeline = PointerTimeline()
        XCTAssertThrowsError(try timeline.point(at: 0, target: Box(x: 1000, y: 100, width: 100, height: 30),
                                                viewport: Box(x: 0, y: 0, width: 800, height: 600)))
    }
}
