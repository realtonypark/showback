import XCTest
@testable import ShowbackCore

final class RunLockTests: XCTestCase {
    func testSecondRunCannotTakeDesktopWhileFirstOwnsIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var first: RunLock? = try RunLock(url: file)
        XCTAssertThrowsError(try RunLock(url: file))
        first?.release()
        first = nil
        XCTAssertNoThrow(try RunLock(url: file))
    }
}
