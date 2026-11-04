import XCTest
@testable import ShowbackCore

final class ApplicationTests: XCTestCase {
    private func withAssets(_ body: () throws -> Void) throws {
        try TestEnv.withValue("/tmp/showback-assets", for: "SHOWBACK_ASSETS", body)
    }

    private func routeName(_ route: LaunchRoute) -> String {
        switch route {
        case .run: return "run"
        case .settings: return "settings"
        case .cli: return "cli"
        }
    }

    private struct RouteCase {
        let args: [String]
        let appBundle: Bool
        let expect: String
    }

    func testParseRoutesCommands() throws {
        let cases = [
            RouteCase(args: ["run", "demo.json"], appBundle: false, expect: "run"),
            RouteCase(args: ["run", "demo.json", "--live-only", "--mute"], appBundle: false, expect: "run"),
            RouteCase(args: ["settings"], appBundle: false, expect: "settings"),
            RouteCase(args: [], appBundle: true, expect: "settings"),
            RouteCase(args: [], appBundle: false, expect: "cli"),
            RouteCase(args: ["doctor"], appBundle: false, expect: "cli"),
            RouteCase(args: ["validate", "demo.json"], appBundle: true, expect: "cli")
        ]
        try withAssets {
            for row in cases {
                let (args, appBundle, expect) = (row.args, row.appBundle, row.expect)
                XCTAssertEqual(routeName(try LaunchRoute.parse(args, appBundle: appBundle)), expect, "args: \(args)")
            }
        }
    }

    func testParseRunCarriesOptionsAndAssets() throws {
        try withAssets {
            let route = try LaunchRoute.parse(["run", "demo.json", "--live-only"], appBundle: false)
            guard case .run(let options, let assets) = route else { return XCTFail("Expected .run, got \(route)") }
            XCTAssertEqual(options.script.lastPathComponent, "demo.json")
            XCTAssertTrue(options.liveOnly)
            XCTAssertFalse(options.mute)
            XCTAssertEqual(assets.root, URL(fileURLWithPath: "/tmp/showback-assets"))
        }
    }

    func testParseSettingsCarriesAssets() throws {
        try withAssets {
            let route = try LaunchRoute.parse([], appBundle: true)
            guard case .settings(let assets) = route else { return XCTFail("Expected .settings, got \(route)") }
            XCTAssertEqual(assets.root, URL(fileURLWithPath: "/tmp/showback-assets"))
        }
    }

    func testParseCliPassesArgumentsThrough() throws {
        try withAssets {
            let route = try LaunchRoute.parse(["doctor", "--guide"], appBundle: false)
            guard case .cli(let arguments) = route else { return XCTFail("Expected .cli, got \(route)") }
            XCTAssertEqual(arguments, ["doctor", "--guide"])
        }
    }

    func testParseRejectsUsageErrors() throws {
        try withAssets {
            XCTAssertThrowsError(try LaunchRoute.parse(["run"], appBundle: false)) { error in
                XCTAssertTrue(error.localizedDescription.contains("Usage"), error.localizedDescription)
            }
            XCTAssertThrowsError(try LaunchRoute.parse(["settings", "extra"], appBundle: false)) { error in
                XCTAssertTrue(error.localizedDescription.contains("Usage"), error.localizedDescription)
            }
        }
    }
}
