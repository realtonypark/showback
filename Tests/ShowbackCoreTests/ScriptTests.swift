import XCTest
@testable import ShowbackCore

final class ScriptTests: XCTestCase {
    func testAcceptsNarratedActionFollowedByCheckedOutcome() throws {
        let data = Data(#"{"version":1,"title":"Login","app":"Fixture","scenes":[{"say":"Open the account.","actions":[{"click":{"role":"button","name":"Sign in"}}],"expect":{"text":"Welcome","timeout":5}},{"say":"The account is open."}]}"#.utf8)
        XCTAssertNoThrow(try DemoScript.parse(data))
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
