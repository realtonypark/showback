import CoreGraphics
import XCTest
@testable import ShowbackCore

final class RunnerTests: XCTestCase {
    @MainActor
    func testRunSceneDrivesNarrationActionsAndEvents() async throws {
        guard let live = TestFiles.onscreenWindow() else {
            throw XCTSkip("No onscreen windows for the scene-orchestration test.")
        }
        let root = try TestFiles.tempDir(self)
        let window = String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "data": [
            ["id": "w-\(live.number)", "title": "Account", "app_name": "Example", "accessible": true,
             "bounds": ["x": live.box.x, "y": live.box.y, "width": live.box.width, "height": live.box.height]]
        ]]), as: UTF8.self)
        let desktop = try FakeDesktop.make(root: root, branches: """
          list-windows*) printf '%s' '\(window)' ;;
          find*) printf '%s' '{"ok":true,"data":{"matches":[{"ref_id":"@s1:e1","name":"Sign in"}]}}' ;;
          get*) printf '%s' '{"ok":true,"data":{"value":{"x":0.0,"y":0.0,"width":10.0,"height":10.0}}}' ;;
          """)
        try await desktop.resolveWindow(app: "Example", title: "Account")
        let wav = root.appendingPathComponent("say.wav")
        try WavFixture.write(to: wav)
        let scriptURL = root.appendingPathComponent("demo.json")
        try Data(#"{"version":1,"title":"Login","app":"Example","window":{"title":"Account"},"scenes":[{"say":"Hi.","actions":[{"click":{"role":"button","name":"Sign in"}}]}]}"#.utf8).write(to: scriptURL)
        let script = try DemoScript.load(scriptURL)
        let bundle = try RunBundle(root: root.appendingPathComponent("run.showback"), script: scriptURL, title: script.title, recording: false)
        let epoch = ProcessInfo.processInfo.systemUptime
        try bundle.start(target: ["app": script.app], epoch: epoch)
        let scene = try XCTUnwrap(script.scenes.first)
        let box = live.box
        let viewport = Box(x: box.x - 1000, y: box.y - 1000, width: box.width + 2000, height: box.height + 2000)
        let context = Runner.SceneContext(script: script, clips: [SpeechClip(url: wav, duration: 0.1)], desktop: desktop,
                                          recording: nil, presentation: nil, bundle: bundle, viewport: viewport,
                                          options: RunOptions(script: scriptURL, output: bundle.root, liveOnly: true, mute: true),
                                          epoch: epoch, target: .display(id: 0))
        var step = "", segments: [NarrationSegment] = []
        try await Runner(assets: Assets(root: root)).runScene(index: 0, scene: scene, context: context, step: &step, segments: &segments)
        XCTAssertEqual(step, "Scene 1, narration")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.url, wav)
        try bundle.finish(.completed, error: nil, mediaReady: false)
        let run = try JSONSerialization.jsonObject(with: Data(contentsOf: bundle.root.appendingPathComponent("run.json"))) as! [String: Any]
        XCTAssertEqual((run["events"] as? [[String: Any]])?.map { $0["kind"] as? String }, ["scene", "narration-start", "point", "action"])
    }

    private func scene(app: String? = nil, windowTitle: String? = nil) -> Scene {
        Scene(say: nil, actions: [], expect: nil, absent: nil, app: app, windowTitle: windowTitle)
    }

    func testResolveSceneTargetPrefersSceneOverrides() {
        let target = Runner.resolveSceneTarget(scene: scene(app: "Other", windowTitle: "Other"), scriptApp: "Example", scriptWindow: "Main")
        XCTAssertEqual(target.app, "Other")
        XCTAssertEqual(target.title, "Other")
    }

    func testResolveSceneTargetFallsBackToScript() {
        let target = Runner.resolveSceneTarget(scene: scene(), scriptApp: "Example", scriptWindow: "Main")
        XCTAssertEqual(target.app, "Example")
        XCTAssertEqual(target.title, "Main")
    }

    func testResolveSceneTargetDropsScriptWindowWhenAppDiffers() {
        let target = Runner.resolveSceneTarget(scene: scene(app: "Other"), scriptApp: "Example", scriptWindow: "Main")
        XCTAssertEqual(target.app, "Other")
        XCTAssertNil(target.title)
    }

    func testTrimmedSegmentShortensInterruptedNarration() {
        let url = URL(fileURLWithPath: "/tmp/say0.m4a")
        let trimmed = Runner.trimmedSegment(NarrationSegment(url: url, start: 10, duration: 5), at: 12)
        XCTAssertEqual(trimmed?.url, url)
        XCTAssertEqual(trimmed?.start, 10)
        XCTAssertEqual(trimmed?.duration ?? -1, 2, accuracy: 1e-9)
    }

    func testTrimmedSegmentCapsAtFullDuration() {
        let trimmed = Runner.trimmedSegment(NarrationSegment(url: URL(fileURLWithPath: "/tmp/say0.m4a"), start: 10, duration: 5), at: 99)
        XCTAssertEqual(trimmed?.duration ?? -1, 5, accuracy: 1e-9)
    }

    func testTrimmedSegmentDropsNegligibleSliver() {
        XCTAssertNil(Runner.trimmedSegment(NarrationSegment(url: URL(fileURLWithPath: "/tmp/say0.m4a"), start: 10, duration: 5), at: 10))
        XCTAssertNil(Runner.trimmedSegment(NarrationSegment(url: URL(fileURLWithPath: "/tmp/say0.m4a"), start: 10, duration: 5), at: 10.005))
    }

    func testCenterInsideAcceptsCenterWithinViewport() {
        let viewport = Box(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(CaptureTarget.centerInside(Box(x: 10, y: 10, width: 20, height: 20), viewport: viewport))
        XCTAssertTrue(CaptureTarget.centerInside(Box(x: -50, y: -50, width: 100, height: 100), viewport: viewport))
        XCTAssertFalse(CaptureTarget.centerInside(Box(x: 200, y: 200, width: 20, height: 20), viewport: viewport))
        XCTAssertFalse(CaptureTarget.centerInside(Box(x: 10, y: 200, width: 20, height: 20), viewport: viewport))
    }

    func testResizeGuardToleratesJitterButRejectsResize() {
        let initial = Box(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNoThrow(try Recording.checkResize(live: Box(x: 5, y: -3, width: 801, height: 599), initial: initial))
        XCTAssertThrowsError(try Recording.checkResize(live: Box(x: 0, y: 0, width: 900, height: 600), initial: initial)) { error in
            XCTAssertTrue(error.localizedDescription.contains("resized"), error.localizedDescription)
        }
    }

    @MainActor
    func testDisplayViewportStaysFixed() throws {
        let initial = Box(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(try CaptureTarget.display(id: 1).liveViewport(window: 999, initial: initial), initial)
    }

    @MainActor
    func testWindowBoundsReadsLiveWindow() throws {
        guard let window = TestFiles.onscreenWindow() else {
            throw XCTSkip("No onscreen windows for the live-bounds test.")
        }
        let live = try Recording.windowBounds(window.number)
        XCTAssertEqual(live.x, window.box.x, accuracy: 2)
        XCTAssertEqual(live.y, window.box.y, accuracy: 2)
        XCTAssertEqual(live.width, window.box.width, accuracy: 2)
        XCTAssertEqual(live.height, window.box.height, accuracy: 2)
        XCTAssertThrowsError(try Recording.windowBounds(UInt32.max)) { error in
            XCTAssertTrue(error.localizedDescription.contains("hidden or closed"), error.localizedDescription)
        }
    }
}
