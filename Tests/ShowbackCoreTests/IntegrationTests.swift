import XCTest
@testable import ShowbackCore

final class IntegrationTests: XCTestCase {
    func testScriptDesktopBundleFlowWritesRunResults() async throws {
        let root = try TestFiles.tempDir(self)
        let scriptURL = root.appendingPathComponent("demo.json")
        try Data(#"{"version":1,"title":"Login","app":"Example","scenes":[{"say":"Open the account.","actions":[{"click":{"role":"button","name":"Sign in"}}]}]}"#.utf8).write(to: scriptURL)
        let script = try DemoScript.load(scriptURL)
        let desktop = try FakeDesktop.make(root: root, branches: """
          find*) printf '%s' '{"ok":true,"data":{"matches":[{"ref_id":"@s1:e1","name":"Sign in"}]}}' ;;
          get*) printf '%s' '{"ok":true,"data":{"value":{"x":0.0,"y":0.0,"width":10.0,"height":10.0}}}' ;;
          """)
        try await desktop.resolveWindow(app: script.app, title: script.windowTitle)
        let bundle = try RunBundle(root: root.appendingPathComponent("run.showback"), script: scriptURL, title: script.title, recording: false)
        try bundle.start(target: ["app": script.app], epoch: ProcessInfo.processInfo.systemUptime)
        let scene = try XCTUnwrap(script.scenes.first)
        try bundle.record(.scene, at: 0, scene: 1, data: ["say": scene.say ?? ""])
        let result = try await desktop.execute(XCTUnwrap(scene.actions.first)) { bounds in
            try bundle.record(.point, at: 0, scene: 1, data: ["x": bounds.x, "y": bounds.y])
        }
        try bundle.record(.action, at: 0, scene: 1, data: result)
        try bundle.attachMedia(pointer: PointerTimeline(), narration: [])
        try bundle.finish(.completed, error: nil, mediaReady: false)
        let run = try JSONSerialization.jsonObject(with: Data(contentsOf: bundle.root.appendingPathComponent("run.json"))) as! [String: Any]
        XCTAssertEqual(run["status"] as? String, "completed")
        XCTAssertEqual(run["title"] as? String, "Login")
        let events = run["events"] as? [[String: Any]] ?? []
        XCTAssertEqual(events.map { $0["kind"] as? String }, ["scene", "point", "action"])
    }
}
