import XCTest
@testable import ShowbackCore

final class ScriptTests: XCTestCase {
    func testAcceptsNativeOptionSelection() {
        let data = Data(#"{"version":1,"title":"Voice","app":"Showback","scenes":[{"actions":[{"select":{"target":{"role":"combobox","name":"Voice"},"option":"Marius"}}],"expect":{"role":"combobox","text":"Marius"}}]}"#.utf8)
        XCTAssertNoThrow(try DemoScript.parse(data))
    }
    func testSceneWindowSwitchRequiresExplicitDisplayCapture() throws {
        let scene = #""scenes":[{"app":"Second app","window":{"title":"Second window"},"say":"Now inspect the other app."}]"#
        let windowOnly = Data("{\"version\":1,\"title\":\"Multi-app\",\"app\":\"First app\",\(scene)}".utf8)
        XCTAssertThrowsError(try DemoScript.parse(windowOnly))
        let explicitDisplay = Data("{\"version\":1,\"title\":\"Multi-app\",\"app\":\"First app\",\"capture\":{\"display\":4},\(scene)}".utf8)
        XCTAssertNoThrow(try DemoScript.parse(explicitDisplay))
    }
    func testAcceptsNarratedActionFollowedByCheckedOutcome() throws {
        let data = Data(#"{"version":1,"title":"Login","app":"Fixture","scenes":[{"say":"Open the account.","actions":[{"click":{"role":"button","name":"Sign in"}}],"expect":{"text":"Welcome","timeout":5}},{"say":"The account is open."}]}"#.utf8)
        XCTAssertNoThrow(try DemoScript.parse(data))
    }

    func testAcceptsAbsentCheckForFixedErrorProof() {
        let data = Data(#"{"version":1,"title":"Fixed","app":"Fixture","scenes":[{"actions":[{"click":{"role":"button","name":"Open"}}],"expect":{"text":"Welcome"},"absent":{"text":"404","timeout":5}}]}"#.utf8)
        XCTAssertNoThrow(try DemoScript.parse(data))
        let bad = Data(#"{"version":1,"title":"Fixed","app":"Fixture","scenes":[{"absent":{"text":"404","timeout":true}}]}"#.utf8)
        XCTAssertThrowsError(try DemoScript.parse(bad))
    }

    func testRejectsUnknownFieldsInsteadOfSilentlySkippingChecks() {
        let data = Data(#"{"version":1,"title":"Login","app":"Fixture","scenes":[{"say":"Done","expects":{"text":"Welcome"}}]}"#.utf8)
        XCTAssertThrowsError(try DemoScript.parse(data))
    }

    func testRejectsUnknownAction() {
        let data = Data(#"{"version":1,"title":"Login","app":"Fixture","scenes":[{"actions":[{"shell":"echo success"}]}]}"#.utf8)
        XCTAssertThrowsError(try DemoScript.parse(data))
    }

    func testRejectsBooleanAndUnboundedTimeouts() {
        for timeout in ["true", "0", "-1", "301"] {
            let data = Data("{\"version\":1,\"title\":\"Login\",\"app\":\"Fixture\",\"scenes\":[{\"expect\":{\"text\":\"Welcome\",\"timeout\":\(timeout)}}]}".utf8)
            XCTAssertThrowsError(try DemoScript.parse(data), timeout)
        }
    }

    func testRejectsEmptyTargetsAndImplicitDisplayCapture() {
        for extra in [#""capture":{"display":true},"scenes":[{"say":"Hello"}]"#,
                      #""scenes":[{"actions":[{"click":{}}]}]"#] {
            let data = Data("{\"version\":1,\"title\":\"Login\",\"app\":\"Fixture\",\(extra)}".utf8)
            XCTAssertThrowsError(try DemoScript.parse(data))
        }
    }
}
