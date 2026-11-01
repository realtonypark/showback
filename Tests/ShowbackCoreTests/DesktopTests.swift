import XCTest
@testable import ShowbackCore

final class DesktopTests: XCTestCase {
    func testRecoversOnlyOwnedSessionBeforeCreatingAnother() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = UUID()
        let marker = root.appendingPathComponent("session.json")
        try JSONEncoder().encode(owner).write(to: marker)
        let log = root.appendingPathComponent("calls")
        let binary = root.appendingPathComponent("desktop")
        let sessions: [String: Any] = ["ok": true, "data": ["sessions": [
            ["session_id": "stale", "name": "Showback \(owner.uuidString)"],
            ["session_id": "unrelated", "name": "Showback \(UUID().uuidString)"],
            ["session_id": "already-ended", "name": "Showback \(owner.uuidString)", "ended_at": 123]
        ]]]
        let list = String(decoding: try JSONSerialization.data(withJSONObject: sessions), as: UTF8.self)
        let windows = String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "data": [first]]), as: UTF8.self)
        let script = """
        #!/bin/sh
        if [ "$1" = --session ]; then shift 2; fi
        printf '%s\\n' "$*" >> '\(log.path)'
        case "$1 $2" in
          'session list') printf '%s' '\(list)' ;;
          'session start') [ -s '\(marker.path)' ] || exit 9; printf '%s' '{"ok":true,"data":{"session_id":"new"}}' ;;
          permissions*) printf '%s' '{"ok":true,"data":{"accessibility":{"state":"granted"}}}' ;;
          list-windows*) printf '%s' '\(windows)' ;;
          *) printf '%s' '{"ok":true,"data":{}}' ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let desktop = Desktop(binary: binary, app: "Example", title: "Account", sessionFile: marker)
        try await desktop.start(recording: false)
        let calls = try String(contentsOf: log, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertEqual(Array(calls.prefix(2)), ["session list", "session end stale"])
        XCTAssertFalse(calls.contains("session end unrelated"))
        XCTAssertFalse(calls.contains("session end already-ended"))
        XCTAssertNotEqual(try JSONDecoder().decode(UUID.self, from: Data(contentsOf: marker)), owner)
        try await desktop.end()
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))

        try JSONEncoder().encode(owner).write(to: marker)
        let failedScript = script.replacingOccurrences(of: "'session start')", with: "'session end') printf '%s' '{\"ok\":false,\"error\":{\"message\":\"recovery blocked\"}}';;\n'session start')")
        try failedScript.write(to: binary, atomically: true, encoding: .utf8)
        try "".write(to: log, atomically: true, encoding: .utf8)
        let retry = Desktop(binary: binary, app: "Example", title: "Account", sessionFile: marker)
        do {
            try await retry.start(recording: false)
            XCTFail("Recovery failure must prevent a new session")
        } catch { XCTAssertTrue(error.localizedDescription.contains("recovery blocked")) }
        XCTAssertEqual(try JSONDecoder().decode(UUID.self, from: Data(contentsOf: marker)), owner)
        XCTAssertFalse(try String(contentsOf: log, encoding: .utf8).contains("session start"))
    }
    let first: [String: Any] = ["id": "w-1", "title": "Account", "app_name": "Example", "accessible": true,
                                "bounds": ["x": -100.0, "y": 10.0, "width": 800.0, "height": 600.0]]
    func testRefusesAmbiguousWindowInsteadOfChoosingFirst() {
        var second = first; second["id"] = "w-2"
        XCTAssertThrowsError(try Desktop.selectWindow([first, second], app: "Example", title: nil))
    }
    func testInaccessibleMatchingWindowStillMakesSelectionAmbiguous() {
        var second = first; second["id"] = "w-2"; second["accessible"] = false
        XCTAssertThrowsError(try Desktop.selectWindow([first, second], app: "Example", title: nil))
    }
    func testSelectsExactWindowTitleAndPreservesNegativeOrigin() throws {
        var other = first; other["title"] = "Account settings"
        let result = try Desktop.selectWindow([first, other], app: "Example", title: "Account")
        XCTAssertEqual(result.id, "w-1")
        XCTAssertEqual(result.bounds.x, -100)
    }
    func testSelectWaitsForSlowWindowThenSucceeds() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = root.appendingPathComponent("count")
        let binary = root.appendingPathComponent("desktop")
        let windows = String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "data": [first]]), as: UTF8.self)
        let script = """
        #!/bin/sh
        if [ "$1" = --session ]; then shift 2; fi
        case "$1 $2" in
          list-windows*)
            n=0; [ -f '\(count.path)' ] && n=$(cat '\(count.path)'); n=$((n+1)); printf '%s' "$n" > '\(count.path)'
            if [ "$n" -lt 2 ]; then printf '%s' '{"ok":true,"data":[]}'; else printf '%s' '\(windows)'; fi ;;
          *) printf '%s' '{"ok":true,"data":{}}' ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let desktop = Desktop(binary: binary, app: "Example", title: "Account", sessionFile: root.appendingPathComponent("s.json"))
        try await desktop.select(app: "Example", title: "Account")
        XCTAssertEqual(desktop.window?.id, "w-1")
    }
    func testFocusRetriesTransientFocusLoss() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = root.appendingPathComponent("count")
        let binary = root.appendingPathComponent("desktop")
        let windows = String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "data": [first]]), as: UTF8.self)
        let script = """
        #!/bin/sh
        if [ "$1" = --session ]; then shift 2; fi
        case "$1 $2" in
          list-windows*) printf '%s' '\(windows)' ;;
          focus-window*)
            n=0; [ -f '\(count.path)' ] && n=$(cat '\(count.path)'); n=$((n+1)); printf '%s' "$n" > '\(count.path)'
            if [ "$n" -lt 2 ]; then printf '%s' '{"ok":false,"error":{"message":"lost focus"}}'; else printf '%s' '{"ok":true,"data":{}}'; fi ;;
          *) printf '%s' '{"ok":true,"data":{}}' ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let desktop = Desktop(binary: binary, app: "Example", title: "Account", sessionFile: root.appendingPathComponent("s.json"))
        try await desktop.select(app: "Example", title: "Account")
        try await desktop.focus()
        XCTAssertEqual(try String(contentsOf: count, encoding: .utf8), "2")
    }
    func testAbsentRetriesTransientFindFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = root.appendingPathComponent("count")
        let binary = root.appendingPathComponent("desktop")
        let windows = String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "data": [first]]), as: UTF8.self)
        let script = """
        #!/bin/sh
        if [ "$1" = --session ]; then shift 2; fi
        case "$1 $2" in
          list-windows*) printf '%s' '\(windows)' ;;
          find*)
            n=0; [ -f '\(count.path)' ] && n=$(cat '\(count.path)'); n=$((n+1)); printf '%s' "$n" > '\(count.path)'
            if [ "$n" -lt 2 ]; then printf '%s' '{"ok":false,"error":{"message":"incomplete"}}'; else printf '%s' '{"ok":true,"data":{"matches":[]}}'; fi ;;
          *) printf '%s' '{"ok":true,"data":{}}' ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let desktop = Desktop(binary: binary, app: "Example", title: "Account", sessionFile: root.appendingPathComponent("s.json"))
        try await desktop.select(app: "Example", title: "Account")
        let absent = Expected(target: Selector(role: nil, name: nil, text: "404", nativeID: nil), timeout: 3)
        let result = try await desktop.waitForAbsent(absent) as? [String: Any]
        XCTAssertEqual(result?["absent"] as? Bool, true)
    }
    func testFindRaisesTraversalTimeoutForDenseTrees() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("calls")
        let binary = root.appendingPathComponent("desktop")
        let windows = String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "data": [first]]), as: UTF8.self)
        let script = """
        #!/bin/sh
        if [ "$1" = --session ]; then shift 2; fi
        printf '%s\\n' "$*" >> '\(log.path)'
        case "$1 $2" in
          list-windows*) printf '%s' '\(windows)' ;;
          find*) printf '%s' '{"ok":true,"data":{"matches":[]}}' ;;
          *) printf '%s' '{"ok":true,"data":{}}' ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let desktop = Desktop(binary: binary, app: "Example", title: "Account", sessionFile: root.appendingPathComponent("s.json"))
        try await desktop.select(app: "Example", title: "Account")
        let absent = Expected(target: Selector(role: nil, name: nil, text: "404", nativeID: nil), timeout: 2)
        let result = try await desktop.waitForAbsent(absent) as? [String: Any]
        XCTAssertEqual(result?["absent"] as? Bool, true)
        XCTAssertTrue(try String(contentsOf: log, encoding: .utf8).contains("--timeout-ms 20000"))
    }
    func testTextPredicateDoesNotMatchWindowOnlyBecauseAChildMatches() {
        let matches: [[String: Any]] = [["role": "window", "name": "Example"], ["role": "statictext", "name": "Welcome", "value": "Welcome"]]
        let target = Selector(role: nil, name: nil, text: "Welcome", nativeID: nil)
        XCTAssertEqual(Desktop.directMatches(matches, target: target).count, 1)
    }
}
