import XCTest
@testable import ShowbackCore

final class ProcessTests: XCTestCase {
    func testArgumentsArePassedLiterally() async throws {
        let result = try await Command.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", "$(touch /tmp/showback-must-not-exist); hello"])
        XCTAssertEqual(result.stdout, "$(touch /tmp/showback-must-not-exist); hello")
    }
    func testReportsExitStatusAndStderrWithoutLosingOutput() async throws {
        let result = try await Command.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf output; printf failure >&2; exit 7"])
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.stdout, "output")
        XCTAssertEqual(result.stderr, "failure")
    }
    func testTerminatesTimedOutCommand() async {
        do {
            _ = try await Command.run(URL(fileURLWithPath: "/bin/sleep"), ["20"], timeout: 0.1)
            XCTFail("Timed-out command succeeded")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
    }
}
