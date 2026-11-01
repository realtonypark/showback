import XCTest
@testable import ShowbackCore

final class PresentationTests: XCTestCase {
    func testNegativeDisplayOriginAndRetinaScaleUseSameTarget() throws {
        let viewport = Box(x: -1200, y: 100, width: 800, height: 600)
        let target = Box(x: -1100, y: 200, width: 200, height: 40)
        var timeline = PointerTimeline()
        try timeline.point(at: 1, target: target, viewport: viewport, kind: "point")
        let frame = try XCTUnwrap(timeline.frame(at: 2, width: 1600, height: 1200))
        XCTAssertEqual(frame.x, 400, accuracy: 0.001)
        XCTAssertEqual(frame.y, 240, accuracy: 0.001)
        XCTAssertNil(timeline.frame(at: 0, width: 1600, height: 1200))
    }
    func testRefusesTargetOutsideSelectedWindow() {
        var timeline = PointerTimeline()
        XCTAssertThrowsError(try timeline.point(at: 0, target: Box(x: 1000, y: 100, width: 100, height: 30),
                                                viewport: Box(x: 0, y: 0, width: 800, height: 600), kind: "click"))
    }
}
