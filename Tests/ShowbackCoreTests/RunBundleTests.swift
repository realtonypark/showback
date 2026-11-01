import XCTest
@testable import ShowbackCore

final class RunBundleTests: XCTestCase {
    func testFailureAndCancellationRemainVisibleInSavedResult() throws {
        for status in [RunStatus.failed, .cancelled] {
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: parent) }
            let script = parent.appendingPathComponent("demo.json")
            try Data("{}".utf8).write(to: script)
            let bundle = try RunBundle(root: parent.appendingPathComponent("run.showback"), script: script, title: "Example", recording: true)
            try bundle.finish(status, error: "Expected state was not reached", mediaReady: false)
            let result = try JSONSerialization.jsonObject(with: Data(contentsOf: bundle.root.appendingPathComponent("run.json"))) as! [String: Any]
            XCTAssertEqual(result["status"] as? String, status.rawValue)
            XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.root.appendingPathComponent(".incomplete").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.root.appendingPathComponent("demo.mp4").path))
        }
    }
    func testRefusesToOverwriteExistingBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keep")
        try Data("original".utf8).write(to: file)
        XCTAssertThrowsError(try RunBundle(root: root, script: file, title: "Example", recording: true))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original")
    }
}
