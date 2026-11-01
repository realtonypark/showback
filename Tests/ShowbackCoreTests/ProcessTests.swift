import XCTest
@testable import ShowbackCore

final class ProcessTests: XCTestCase {
    func testInheritsLaunchingEnvironment() async throws {
        let expected = try XCTUnwrap(ProcessInfo.processInfo.environment["HOME"])
        let result = try await Command.run(URL(fileURLWithPath: "/usr/bin/printenv"), ["HOME"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), expected)
    }
    func testBinaryOutputIsWrittenWithoutTextDecoding() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = file.appendingPathExtension("input")
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: source) }
        try Data([0, 255, 10]).write(to: source)
        let result = try await Command.run(URL(fileURLWithPath: "/bin/cat"), [source.path], stdoutFile: file)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(try Data(contentsOf: file), Data([0, 255, 10]))
    }
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
