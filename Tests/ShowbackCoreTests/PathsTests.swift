import XCTest
@testable import ShowbackCore

final class PathsTests: XCTestCase {
    private func withAssetsEnv(_ value: String?, _ body: () throws -> Void) rethrows {
        try TestEnv.withValue(value, for: "SHOWBACK_ASSETS", body)
    }

    func testAbsoluteAssetsEnvSelectsRoot() throws {
        try withAssetsEnv("/tmp/showback-assets") {
            XCTAssertEqual(try Paths.assets().root, URL(fileURLWithPath: "/tmp/showback-assets"))
        }
    }

    func testRelativeAssetsEnvThrows() throws {
        try withAssetsEnv("relative/path") {
            XCTAssertThrowsError(try Paths.assets()) { error in
                XCTAssertTrue(error.localizedDescription.contains("absolute path"), error.localizedDescription)
            }
        }
    }

    func testMissingAssetsEnvOutsideAppThrows() throws {
        try withAssetsEnv(nil) {
            XCTAssertThrowsError(try Paths.assets()) { error in
                XCTAssertTrue(error.localizedDescription.contains("SHOWBACK_ASSETS"), error.localizedDescription)
            }
        }
    }
}
