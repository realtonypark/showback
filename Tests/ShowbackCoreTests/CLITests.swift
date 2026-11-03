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

    func testDoctorValidatesInstalledSkill() throws {
        let app = URL(fileURLWithPath: "/absolute/Applications/Showback.app")
        let skill = CLI.skillURL(forApp: app)
        XCTAssertEqual(skill.path, "/absolute/.agents/skills/showback/SKILL.md")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = root.appendingPathComponent("invalid")
        try Data("not a skill".utf8).write(to: invalid)
        XCTAssertThrowsError(try CLI.validateSkill(at: invalid))
        XCTAssertThrowsError(try CLI.validateSkill(at: root.appendingPathComponent("missing")))
        try Data("---\nname: showback\ndescription: demo\n---\n".utf8).write(to: invalid)
        XCTAssertNoThrow(try CLI.validateSkill(at: invalid))
    }

    func testDoctorSummarizesPermissions() {
        let output = #"{"data":{"permissions":{"accessibility":{"state":"denied"},"automation":{"state":"unknown"},"screen_recording":{"state":"granted"}}}}"#
        XCTAssertEqual(CLI.permissionSummary(output), "Accessibility denied, Automation unknown, Screen recording granted")
    }

    func testValidateHelpDoesNotTreatFlagAsScript() async throws {
        let handled = try await CLI.perform(["validate", "--help"])
        XCTAssertTrue(handled)
    }
}
