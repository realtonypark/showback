import Foundation

public struct Box: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
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
    private(set) var app: String
    private(set) var title: String?
    public private(set) var session: String?
    public private(set) var window: DesktopWindow?
    private let sessionFile: URL
    private var sessionOwner: UUID?

    public init(binary: URL, app: String, title: String?, sessionFile: URL) {
        self.binary = binary; self.app = app; self.title = title; self.sessionFile = sessionFile
    }

    public func start(recording: Bool) async throws {
        try await recoverSession()
        let owner = UUID()
        try FileManager.default.createDirectory(at: sessionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Persist ownership before creation, so even a lost create response can be recovered.
        try JSONEncoder().encode(owner).write(to: sessionFile, options: .atomic)
        sessionOwner = owner
        guard let result = try await call(["session", "start", "--name", Self.label(owner)]) as? [String: Any],
              let id = result["session_id"] as? String else { throw Failure("Desktop returned no session ID.") }
        session = id
        let status = try await call(["permissions"])
        guard let permissions = status as? [String: Any],
              (permissions["accessibility"] as? [String: Any])?["state"] as? String == "granted" else {
            throw Failure("Accessibility permission is required. Run showback desktop permissions --guide.")
        }
        if recording, (permissions["screen_recording"] as? [String: Any])?["state"] as? String != "granted" {
            throw Failure("Screen Recording permission is required. Run showback desktop permissions --guide.")
        }
        try await select(app: app, title: title)
    }

    func select(app: String, title: String?) async throws {
        // ponytail: poll for a slow launch; fail fast only on ambiguity, which waiting cannot fix.
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while true {
            let windows = try await call(["list-windows", "--app", app]) as? [[String: Any]] ?? []
            do {
                let selected = try Self.selectWindow(windows, app: app, title: title)
                self.app = app; self.title = title; self.window = selected
                return
            } catch {
                let matches = windows.filter {
                    ($0["app_name"] as? String)?.caseInsensitiveCompare(app) == .orderedSame &&
                    $0["minimized"] as? Bool != true && $0["visible"] as? Bool != false &&
                    (title == nil || ($0["title"] as? String) == title)
                }
                guard matches.count <= 1, ProcessInfo.processInfo.systemUptime < deadline else { throw error }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    public func end() async throws {
        guard sessionOwner != nil else { return }
        if let session {
            _ = try await call(["session", "end", session])
            self.session = nil
            try FileManager.default.removeItem(at: sessionFile)
        } else {
            try await recoverSession()
        }
        sessionOwner = nil
    }

    private static func label(_ owner: UUID) -> String { "Showback \(owner.uuidString)" }

    private func recoverSession() async throws {
        guard FileManager.default.fileExists(atPath: sessionFile.path) else { return }
        let owner: UUID
        do { owner = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: sessionFile)) }
        catch { throw Failure("Cannot read desktop session ownership at \(sessionFile.path): \(error.localizedDescription)") }
        guard let result = try await call(["session", "list"]) as? [String: Any],
              let sessions = result["sessions"] as? [[String: Any]] else {
            throw Failure("Cannot recover the previous desktop session: incomplete session inventory.")
        }
        for entry in sessions where entry["name"] as? String == Self.label(owner) &&
            (entry["ended_at"] == nil || entry["ended_at"] is NSNull) {
            guard let id = entry["session_id"] as? String, !id.isEmpty else {
                throw Failure("Cannot recover the previous desktop session: missing session ID.")
            }
            _ = try await call(["session", "end", id])
        }
        try FileManager.default.removeItem(at: sessionFile)
    }

    public func focus() async throws {
        // ponytail: focus is idempotent presentation, not a mutating action; poll through transient loss.
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while true {
            do { _ = try await call(["focus-window", "--window-id", try selected().id]); return }
            catch {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw error }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    public func selected() throws -> DesktopWindow {
        guard let window else { throw Failure("No capture window has been selected.") }
        return window
    }

    public func execute(_ action: Action, willAct: (Box) async throws -> Void) async throws -> Any? {
        var selector: Selector
        var command: String
        var suffix: [String] = []
        switch action {
        case .wait(let expected): return try await waitFor(expected)
        case .press(let key): return try await call(["press", key, "--window-id", selected().id])
        case .point(let target): selector = target; command = "point"
        case .click(let target): selector = target; command = "click"
        case .type(let target, let text): selector = target; command = "type"; suffix = [text]
        case .select(let target, let option): selector = target; command = "select"; suffix = [option]
        case .scroll(let target, let direction, let amount):
            selector = target; command = "scroll"; suffix = ["--direction", direction, "--amount", String(amount)]
        case .setValue(let target, let text): selector = target; command = "set-value"; suffix = [text]
        case .verb(let name, let target): selector = target; command = name
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
        try await willAct(bounds)
        try Task.checkCancellation()
        if command == "point" { return ["pointed": true] }
        return try await call([command, ref!] + suffix)
    }

    @discardableResult public func waitFor(_ expected: Expected) async throws -> Any {
        let deadline = ProcessInfo.processInfo.systemUptime + expected.timeout
        var lastError: Error?
        repeat {
            try Task.checkCancellation()
            // ponytail: find is read-only; retry transient incomplete reads inside the budget.
            do {
                let matches = try await find(expected.target, deadline: deadline)
                lastError = nil
                if !matches.isEmpty { return ["matched": matches.count, "target": matches.first!] }
            } catch { lastError = error }
            try await Task.sleep(nanoseconds: 150_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        if let lastError { throw lastError }
        throw Failure("Expected UI state did not appear within \(expected.timeout) seconds.")
    }

    @discardableResult public func waitForAbsent(_ expected: Expected) async throws -> Any {
        let deadline = ProcessInfo.processInfo.systemUptime + expected.timeout
        var lastError: Error?
        repeat {
            try Task.checkCancellation()
            do {
                let matches = try await find(expected.target, deadline: deadline)
                lastError = nil
                if matches.isEmpty { return ["absent": true] }
            } catch { lastError = error }
            try await Task.sleep(nanoseconds: 150_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        if let lastError { throw lastError }
        throw Failure("Expected UI state was still present after \(expected.timeout) seconds.")
    }

    private func find(_ target: Selector, deadline: Double? = nil) async throws -> [[String: Any]] {
        // ponytail: dense web trees exhaust the 5s default; cap each attempt at the caller's remaining budget (max 20s).
        let timeoutMs = deadline.map { max(1, min(20_000, Int(($0 - ProcessInfo.processInfo.systemUptime) * 1000))) } ?? 20_000
        // Text targets match by substring (see directMatches), so --exact applies only without text.
        var args = ["find", "--app", app, "--window-id", try selected().id, "--limit", "0", "--timeout-ms", String(timeoutMs)]
        if target.text == nil { args.append("--exact") }
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
            $0["minimized"] as? Bool != true && $0["visible"] as? Bool != false &&
            (title == nil || ($0["title"] as? String) == title)
        }
        guard matches.count == 1, let match = matches.first, let id = match["id"] as? String,
              id.hasPrefix("w-"), let number = UInt32(id.dropFirst(2)), number > 0 else {
            let choices = windows.map { "\($0["id"] ?? "?"): \($0["title"] ?? "")" }.joined(separator: ", ")
            throw Failure("Expected one accessible window for \(app); found \(matches.count). Candidates: \(choices)")
        }
        guard match["accessible"] as? Bool == true else {
            throw Failure("The selected window is not accessible yet. Wait for the app to be ready, then retry. Run showback desktop permissions if this persists.")
        }
        return try DesktopWindow(id: id, title: match["title"] as? String ?? "", bounds: Box(match["bounds"]))
    }

    static func directMatches(_ matches: [[String: Any]], target: Selector) -> [[String: Any]] {
        // Text matches by substring; name stays exact so a combined selector cannot pass on a near-name.
        matches.filter { match in
            if let name = target.name, (match["name"] as? String)?.caseInsensitiveCompare(name) != .orderedSame { return false }
            guard let text = target.text else { return true }
            return ["name", "value", "description"].compactMap { match[$0] as? String }.contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }
}
