import XCTest
@testable import ShowbackCore

final class DesktopTests: XCTestCase {
    let first: [String: Any] = ["id": "w-1", "title": "Account", "app_name": "Example", "accessible": true,
                                "bounds": ["x": -100.0, "y": 10.0, "width": 800.0, "height": 600.0]]
    func testRefusesAmbiguousWindowInsteadOfChoosingFirst() {
        var second = first; second["id"] = "w-2"
        XCTAssertThrowsError(try Desktop.selectWindow([first, second], app: "Example", title: nil))
    }
    func testSelectsExactWindowTitleAndPreservesNegativeOrigin() throws {
        var other = first; other["title"] = "Account settings"
        let result = try Desktop.selectWindow([first, other], app: "Example", title: "Account")
        XCTAssertEqual(result.id, "w-1")
        XCTAssertEqual(result.bounds.x, -100)
    }
    func testTextPredicateDoesNotMatchWindowOnlyBecauseAChildMatches() {
        let matches: [[String: Any]] = [["role": "window", "name": "Example"], ["role": "statictext", "name": "Welcome", "value": "Welcome"]]
        let target = Selector(role: nil, name: nil, text: "Welcome", nativeID: nil)
        XCTAssertEqual(Desktop.directMatches(matches, target: target).count, 1)
    }
}
