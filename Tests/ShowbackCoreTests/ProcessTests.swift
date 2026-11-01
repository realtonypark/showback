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
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("showback-literal-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let text = "$(touch " + marker.path + "); hello"
        let result = try await Command.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", text])
        XCTAssertEqual(result.stdout, text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
    func testReportsExitStatusAndStderrWithoutLosingOutput() async throws {
        let result = try await Command.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf output; printf failure >&2; exit 7"])
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.stdout, "output")
        XCTAssertEqual(result.stderr, "failure")
    }
    func testLimitsOutputBeforeTimeoutIncludingBinaryFiles() async throws {
        for mode in ["stdout", "stderr", "file"] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            let redirect = mode == "stderr" ? " >&2" : ""
            do {
                _ = try await Command.run(URL(fileURLWithPath: "/bin/sh"),
                    ["-c", "head -c 17825792 /dev/zero" + redirect + "; sleep 5"], timeout: 2,
                    stdoutFile: mode == "file" ? file : nil)
                XCTFail("Oversized output succeeded")
            } catch { XCTAssertTrue(error.localizedDescription.contains("output exceeds"), error.localizedDescription) }
            if mode == "file" { XCTAssertLessThanOrEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 16_777_216) }
        }
    }
    func testExitObservedAfterEmptyReadDoesNotDiscardFinalBytes() throws {
        let pipe = Pipe()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url); try? pipe.fileHandleForWriting.close() }
        try Data().write(to: url)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        let final = Data("last bytes before exit".utf8)
        var exited = false
        var failures: [String] = []
        Command.drain(pipe, into: file, isRunning: {
            if !exited {
                try! pipe.fileHandleForWriting.write(contentsOf: final)
                exited = true
            }
            return false
        }, limit: 100, onFailure: { failures.append($0) })
        XCTAssertEqual(try Data(contentsOf: url), final)
        XCTAssertTrue(failures.isEmpty)
    }

    func testDescendantHoldingPipeDoesNotDelayDirectChildOutput() async throws {
        let result = try await Command.run(URL(fileURLWithPath: "/bin/sh"),
            ["-c", "sleep 10 & printf '%s' \"$!\" >&2; printf final; exit 0"], timeout: 2)
        let descendant = try XCTUnwrap(Int32(result.stderr))
        defer { kill(descendant, SIGTERM) }
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "final")
        XCTAssertEqual(kill(descendant, 0), 0, "Command must return while the descendant still holds its pipes")
    }

    func testTerminatesTimedOutCommand() async {
        do {
            _ = try await Command.run(URL(fileURLWithPath: "/bin/sleep"), ["20"], timeout: 0.1)
            XCTFail("Timed-out command succeeded")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
    }
}
