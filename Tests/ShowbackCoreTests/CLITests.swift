import XCTest
@testable import ShowbackCore

final class CLITests: XCTestCase {
    func testRecordedRunIsDefaultAndMuteDoesNotDisableRecording() throws {
        let options = try RunOptions.parse(["demo.json", "--mute", "--out", "/tmp/example.showback"])
        XCTAssertFalse(options.liveOnly)
        XCTAssertTrue(options.mute)
        XCTAssertEqual(options.output.path, "/tmp/example.showback")
    }
    func testRejectsUnknownAndDuplicateFlags() {
        for args in [["demo.json", "--slient"], ["demo.json", "--mute", "--mute"], ["demo.json", "--out"]] {
            XCTAssertThrowsError(try RunOptions.parse(args))
        }
    }
}
