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

        let root = try TestFiles.tempDir(self)
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

    func testDoctorRequiresBothGrantsBeforeHidingGuideHint() {
        let granted = #"{"data":{"permissions":{"accessibility":{"state":"granted"},"automation":{"state":"unknown"},"screen_recording":{"state":"granted"}}}}"#
        XCTAssertTrue(CLI.requiredGrantsReady(granted))
        for output in [
            #"{"data":{"permissions":{"accessibility":{"state":"denied"},"automation":{"state":"granted"},"screen_recording":{"state":"granted"}}}}"#,
            #"{"data":{"permissions":{"accessibility":{"state":"unknown"},"automation":{"state":"granted"},"screen_recording":{"state":"granted"}}}}"#,
            #"{"data":{"permissions":{"accessibility":{"state":"granted"},"automation":{"state":"granted"},"screen_recording":{"state":"unknown"}}}}"#,
            "not json"
        ] {
            XCTAssertFalse(CLI.requiredGrantsReady(output))
        }
    }

    func testValidateHelpDoesNotTreatFlagAsScript() async throws {
        try await CLI.dispatch(["validate", "--help"])
    }

    func testHelpListsEveryTopLevelCommand() {
        for command in ["run", "validate", "settings", "doctor", "desktop", "install-assets", "--version"] {
            XCTAssertTrue(CLI.help.contains(command), "help omits \(command)")
        }
    }

    func testUnknownCommandThrowsFailure() async {
        do {
            try await CLI.dispatch(["frobnicate"])
            XCTFail("expected unknown command to throw")
        } catch let failure as Failure {
            XCTAssertTrue(failure.message.contains("Unknown command"))
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
