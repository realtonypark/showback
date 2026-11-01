import Foundation

public struct Box: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    init(_ value: Any?) throws {
        guard let fields = value as? [String: Any], let x = fields["x"] as? Double, let y = fields["y"] as? Double,
              let width = fields["width"] as? Double, let height = fields["height"] as? Double,
              [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { throw Failure("Desktop returned invalid geometry.") }
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct DesktopWindow {
    public let id: String
    public let title: String
    public let bounds: Box
    public var number: UInt32 { UInt32(id.dropFirst(2))! }
}

public final class Desktop {
    let binary: URL
    let app: String
    let title: String?
    public private(set) var session: String?
    public private(set) var window: DesktopWindow?

    public init(binary: URL, app: String, title: String?) {
        self.binary = binary; self.app = app; self.title = title
    }

    public func start(recording: Bool) async throws {
        guard let result = try await call(["session", "start", "--name", "Showback"]) as? [String: Any],
              let id = result["session_id"] as? String else { throw Failure("Desktop returned no session ID.") }
        session = id
        let status = try await call(["permissions"])
        guard let permissions = status as? [String: Any],
              (permissions["accessibility"] as? [String: Any])?["state"] as? String == "granted" else {
            throw Failure("Accessibility permission is required. Run agent-desktop permissions --guide.")
        }
        if recording, (permissions["screen_recording"] as? [String: Any])?["state"] as? String != "granted" {
            throw Failure("Screen Recording permission is required. Run agent-desktop permissions --guide.")
        }
        let windows = try await call(["list-windows", "--app", app]) as? [[String: Any]] ?? []
        window = try Self.selectWindow(windows, app: app, title: title)
    }

    public func end() async throws {
        guard let session else { return }
        _ = try await call(["session", "end", session])
        self.session = nil
    }

    public func focus() async throws {
        _ = try await call(["focus-window", "--window-id", try selected().id])
    }

    public func selected() throws -> DesktopWindow {
        guard let window else { throw Failure("No capture window has been selected.") }
        return window
    }

    public func execute(_ action: Action, willAct: (Box, String) async throws -> Void) async throws -> Any? {
        var selector: Selector
        var command: String
        var suffix: [String] = []
        switch action {
        case .wait(let expected): return try await waitFor(expected)
        case .press(let key): return try await call(["press", key, "--window-id", selected().id])
        case .point(let target): selector = target; command = "point"
        case .click(let target): selector = target; command = "click"
        case .type(let target, let text): selector = target; command = "type"; suffix = [text]
        case .scroll(let target, let direction, let amount):
            selector = target; command = "scroll"; suffix = ["--direction", direction, "--amount", String(amount)]
        }
        let matches = try await find(selector)
        guard matches.count == 1, let match = matches.first else {
            throw Failure("Expected one \(command) target; found \(matches.count). Narrow the selector.")
        }
        let ref = match["ref_id"] as? String
        let bounds: Box
        if let ref {
            let result = try await call(["get", ref, "--property", "bounds"]) as? [String: Any]
            bounds = try Box(result?["value"])
        } else { bounds = try Box(match["bounds"]) }
        guard command == "point" || ref != nil else { throw Failure("The selected element is not actionable.") }
        try await willAct(bounds, command)
        try Task.checkCancellation()
        if command == "point" { return ["pointed": true] }
        return try await call([command, ref!] + suffix)
    }

    @discardableResult public func waitFor(_ expected: Expected) async throws -> Any {
        let deadline = ProcessInfo.processInfo.systemUptime + expected.timeout
        repeat {
            try Task.checkCancellation()
            let matches = try await find(expected.target)
            if !matches.isEmpty { return ["matched": matches.count, "target": matches.first!] }
            try await Task.sleep(nanoseconds: 150_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw Failure("Expected UI state did not appear within \(expected.timeout) seconds.")
    }

    public func screenshot(_ url: URL) async throws {
        _ = try await call(["screenshot", url.path, "--app", app, "--window-id", selected().id])
    }

    private func find(_ target: Selector) async throws -> [[String: Any]] {
        var args = ["find", "--app", app, "--window-id", try selected().id, "--exact", "--limit", "0"]
        for (flag, value) in [("--role", target.role), ("--name", target.name), ("--text", target.text), ("--native-id", target.nativeID)] {
            if let value { args += [flag, value] }
        }
        guard let result = try await call(args) as? [String: Any], let matches = result["matches"] as? [[String: Any]],
              result["truncated"] as? Bool != true else { throw Failure("Desktop returned an incomplete target search.") }
        return Self.directMatches(matches, target: target)
    }

    @discardableResult private func call(_ args: [String]) async throws -> Any {
        let scope = session.map { ["--session", $0] } ?? []
        let result = try await Command.run(binary, scope + args, timeout: 35)
        guard let response = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any] else {
            throw Failure("agent-desktop \(args.first ?? ""): \(result.stderr.isEmpty ? result.stdout : result.stderr)")
        }
        guard result.status == 0, response["ok"] as? Bool == true else {
            let error = response["error"] as? [String: Any] ?? [:]
            let detail = String(data: try JSONSerialization.data(withJSONObject: error, options: [.sortedKeys]), encoding: .utf8) ?? "Unknown error"
            throw Failure("agent-desktop \(args.first ?? ""): \(detail)")
        }
        return response["data"] ?? [:]
    }

    static func selectWindow(_ windows: [[String: Any]], app: String, title: String?) throws -> DesktopWindow {
        let matches = windows.filter {
            ($0["app_name"] as? String)?.caseInsensitiveCompare(app) == .orderedSame &&
            $0["accessible"] as? Bool == true && $0["minimized"] as? Bool != true && $0["visible"] as? Bool != false &&
            (title == nil || ($0["title"] as? String) == title)
        }
        guard matches.count == 1, let match = matches.first, let id = match["id"] as? String,
              id.hasPrefix("w-"), let number = UInt32(id.dropFirst(2)), number > 0 else {
            let choices = windows.map { "\($0["id"] ?? "?"): \($0["title"] ?? "")" }.joined(separator: ", ")
            throw Failure("Expected one accessible window for \(app); found \(matches.count). Candidates: \(choices)")
        }
        return try DesktopWindow(id: id, title: match["title"] as? String ?? "", bounds: Box(match["bounds"]))
    }

    static func directMatches(_ matches: [[String: Any]], target: Selector) -> [[String: Any]] {
        guard let text = target.text else { return matches }
        return matches.filter { match in
            ["name", "value", "description"].compactMap { match[$0] as? String }.contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }
}
