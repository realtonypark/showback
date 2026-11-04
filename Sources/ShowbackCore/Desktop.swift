import Foundation

struct Box: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    init(_ value: Any?) throws {
        guard let fields = value as? [String: Any], let x = fields["x"] as? Double, let y = fields["y"] as? Double,
              let width = fields["width"] as? Double, let height = fields["height"] as? Double,
              [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { throw Failure("Desktop returned invalid geometry.") }
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

struct DesktopWindow {
    let id: String
    let title: String
    let bounds: Box
    let number: UInt32
}

/// One entry from agent-desktop list-windows.
struct ListedWindow {
    let raw: [String: Any]
    init(_ raw: [String: Any]) { self.raw = raw }
    func matches(app: String, title: String?) -> Bool {
        (raw["app_name"] as? String)?.caseInsensitiveCompare(app) == .orderedSame &&
        raw["minimized"] as? Bool != true && raw["visible"] as? Bool != false &&
        (title == nil || (raw["title"] as? String) == title)
    }
    var id: String? { raw["id"] as? String }
    var title: String? { raw["title"] as? String }
    var accessible: Bool { raw["accessible"] as? Bool == true }
}

/// A JSON-serializable object returned by desktop queries.
typealias DesktopResult = [String: Any]

/// Abort a poll loop immediately, rethrowing the wrapped error.
private struct PollFatal: Error { let cause: Error }

/// Agent-desktop permission payload keys and states, shared by Desktop gating and CLI.doctor.
enum PermissionGrant {
    static let accessibility = "accessibility"
    static let automation = "automation"
    static let screenRecording = "screen_recording"
    static let granted = "granted"
    static func state(of key: String, in permissions: [String: Any]) -> String? {
        (permissions[key] as? [String: Any])?["state"] as? String
    }
    static func isGranted(_ key: String, in permissions: [String: Any]) -> Bool {
        state(of: key, in: permissions) == granted
    }
}

final class Desktop {
    let binary: URL
    private(set) var app: String
    private(set) var title: String?
    private(set) var session: String?
    private(set) var window: DesktopWindow?
    private let sessionFile: URL
    private var sessionOwner: UUID?

    init(binary: URL, app: String, title: String?, sessionFile: URL) {
        self.binary = binary; self.app = app; self.title = title; self.sessionFile = sessionFile
    }

    /// - Throws: `Failure` for session, permission, or window-selection errors.
    func start(recording: Bool) async throws {
        try await recoverSession()
        let owner = UUID()
        try FileManager.default.createDirectory(at: sessionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Persist ownership before creation, so even a lost create response can be recovered.
        try JSONEncoder().encode(owner).write(to: sessionFile, options: .atomic)
        sessionOwner = owner
        guard let result = try await invokeRuntime(["session", "start", "--name", Self.label(owner)]) as? [String: Any],
              let id = result["session_id"] as? String else { throw Failure("Desktop returned no session ID.") }
        session = id
        let status = try await invokeRuntime(["permissions"])
        guard let permissions = status as? [String: Any],
              PermissionGrant.isGranted(PermissionGrant.accessibility, in: permissions) else {
            throw Failure("Accessibility permission is required. Run showback desktop permissions --guide.")
        }
        if recording, !PermissionGrant.isGranted(PermissionGrant.screenRecording, in: permissions) {
            throw Failure("Screen Recording permission is required. Run showback desktop permissions --guide.")
        }
        try await resolveWindow(app: app, title: title)
    }

    /// - Throws: `Failure` when no matching window appears within the timeout, or selection is ambiguous.
    func resolveWindow(app: String, title: String?, timeout: Double = 15) async throws {
        // ponytail: poll for a slow launch; fail fast only on ambiguity, which waiting cannot fix.
        _ = try await poll(timeout: timeout, interval: 250_000_000) { _ in
            let windows = try await invokeRuntime(["list-windows", "--app", app]) as? [[String: Any]] ?? []
            do {
                let selected = try Self.selectWindow(windows, app: app, title: title)
                self.app = app; self.title = title; self.window = selected
                return ()
            } catch {
                guard Self.matchingWindows(windows, app: app, title: title).count <= 1 else { throw PollFatal(cause: error) }
                throw error
            }
        }
    }

    /// - Throws: `Failure` when the previous session cannot be recovered or ended.
    func end() async throws {
        guard sessionOwner != nil else { return }
        if let session {
            _ = try await invokeRuntime(["session", "end", session])
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
        do {
            owner = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: sessionFile))
        } catch {
            throw Failure("Cannot read desktop session ownership at \(sessionFile.path): \(error.localizedDescription)")
        }
        guard let result = try await invokeRuntime(["session", "list"]) as? [String: Any],
              let sessions = result["sessions"] as? [[String: Any]] else {
            throw Failure("Cannot recover the previous desktop session: incomplete session inventory.")
        }
        for entry in sessions where entry["name"] as? String == Self.label(owner) &&
            (entry["ended_at"] == nil || entry["ended_at"] is NSNull) {
            guard let id = entry["session_id"] as? String, !id.isEmpty else {
                throw Failure("Cannot recover the previous desktop session: missing session ID.")
            }
            _ = try await invokeRuntime(["session", "end", id])
        }
        try FileManager.default.removeItem(at: sessionFile)
    }

    /// - Throws: `Failure` when the window cannot be focused within 5 seconds.
    func focus() async throws {
        // ponytail: focus is idempotent presentation, not a mutating action; poll through transient loss.
        _ = try await poll(timeout: 5, interval: 250_000_000) { _ in
            _ = try await invokeRuntime(["focus-window", "--window-id", try currentWindow.id])
            return ()
        }
    }

    /// - Throws: `Failure` when no capture window has been selected.
    var currentWindow: DesktopWindow {
        get throws {
            guard let window else { throw Failure("No capture window has been selected.") }
            return window
        }
    }

    /// - Throws: `Failure` for ambiguous or non-actionable targets, timeouts, and desktop errors; `CancellationError` when cancelled.
    /// - Returns: Arbitrary JSON from the desktop runtime (`Any?`), not a `DesktopResult`: actions forward unshaped runtime payloads.
    func execute(_ action: Action, willAct: (Box) async throws -> Void) async throws -> Any? {
        switch action {
        case .wait(let expected): return try await waitFor(expected)
        case .press(let key): return try await invokeRuntime(["press", key, "--window-id", currentWindow.id])
        case .point(let target):
            let match = try await uniqueMatch(target, command: "point")
            try await willAct(try bounds(of: match))
            try Task.checkCancellation()
            return ["pointed": true]
        case .click(let target): return try await act(target, command: "click", willAct: willAct)
        case .type(let target, let text): return try await act(target, command: "type", suffix: [text], willAct: willAct)
        case .select(let target, let option): return try await act(target, command: "select", suffix: [option], willAct: willAct)
        case .scroll(let target, let direction, let amount):
            return try await act(target, command: "scroll", suffix: ["--direction", direction, "--amount", String(amount)], willAct: willAct)
        case .setValue(let target, let text): return try await act(target, command: "set-value", suffix: [text], willAct: willAct)
        case .verb("scroll-to", let target):
            // Reveal first: presenting the old, offscreen bounds would block the scroll itself.
            let first = try await uniqueMatch(target, command: "scroll-to")
            guard let ref = first["ref_id"] as? String else { throw Failure("The selected element is not actionable.") }
            let scrollResult = try await invokeRuntime(["scroll-to", ref])
            let match = try await uniqueMatch(target, command: "scroll-to")
            try await willAct(try bounds(of: match))
            try Task.checkCancellation()
            return scrollResult
        case .verb(let name, let target): return try await act(target, command: name, willAct: willAct)
        }
    }

    private func act(_ target: Selector, command: String, suffix: [String] = [], willAct: (Box) async throws -> Void) async throws -> Any? {
        let match = try await uniqueMatch(target, command: command)
        guard let ref = match["ref_id"] as? String else { throw Failure("The selected element is not actionable.") }
        try await willAct(try bounds(of: match))
        try Task.checkCancellation()
        return try await invokeRuntime([command, ref] + suffix)
    }

    private func bounds(of match: [String: Any]) async throws -> Box {
        if let ref = match["ref_id"] as? String {
            let result = try await invokeRuntime(["get", ref, "--property", "bounds"]) as? [String: Any]
            return try Box(result?["value"])
        }
        return try Box(match["bounds"])
    }

    private func uniqueMatch(_ target: Selector, command: String) async throws -> [String: Any] {
        let matches = try await find(target)
        guard matches.count == 1, let match = matches.first else {
            throw Failure("Expected one \(command) target (\(target)); found \(matches.count). Narrow the selector using a fresh desktop find.")
        }
        return match
    }

    /// - Throws: `Failure` when the expected state does not appear within the timeout; `CancellationError` when cancelled.
    @discardableResult func waitFor(_ expected: Expected) async throws -> DesktopResult {
        // ponytail: find is read-only; retry transient incomplete reads inside the budget.
        guard let found = try await poll(timeout: expected.timeout, interval: 150_000_000, body: { deadline -> [String: Any]? in
            let matches = try await find(expected.target, deadline: deadline)
            guard let first = matches.first else { return nil }
            return ["matched": matches.count, "target": first]
        }) else { throw Failure("Expected UI state did not appear within \(expected.timeout) seconds.") }
        return found
    }

    /// - Throws: `Failure` when the state is still present after the timeout; `CancellationError` when cancelled.
    @discardableResult func waitForAbsent(_ expected: Expected) async throws -> DesktopResult {
        guard let found = try await poll(timeout: expected.timeout, interval: 150_000_000, body: { deadline in
            let matches = try await find(expected.target, deadline: deadline)
            return matches.isEmpty ? ["absent": true] : nil
        }) else { throw Failure("Expected UI state was still present after \(expected.timeout) seconds.") }
        return found
    }

    private func poll<T>(timeout: Double, interval: UInt64, body: (Double) async throws -> T?) async throws -> T? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var lastError: Error?
        repeat {
            try Task.checkCancellation()
            do {
                if let value = try await body(deadline) { return value }
                lastError = nil
            } catch let fatal as PollFatal {
                throw fatal.cause
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: interval)
        } while ProcessInfo.processInfo.systemUptime < deadline
        if let lastError { throw lastError }
        return nil
    }

    private func find(_ target: Selector, deadline: Double? = nil) async throws -> [[String: Any]] {
        // ponytail: dense web trees exhaust the 5s default; cap each attempt at the caller's remaining budget (max 20s).
        let timeoutMs = deadline.map { max(1, min(20_000, Int(($0 - ProcessInfo.processInfo.systemUptime) * 1000))) } ?? 20_000
        // Text targets match by substring (see directMatches), so --exact applies only without text.
        var args = ["find", "--app", app, "--window-id", try currentWindow.id, "--limit", "0", "--timeout-ms", String(timeoutMs)]
        if target.text == nil { args.append("--exact") }
        for (flag, value) in [("--role", target.role), ("--name", target.name), ("--text", target.text), ("--native-id", target.nativeID)] {
            if let value { args += [flag, value] }
        }
        guard let result = try await invokeRuntime(args) as? [String: Any], let matches = result["matches"] as? [[String: Any]],
              result["truncated"] as? Bool != true else { throw Failure("Desktop returned an incomplete target search.") }
        return Self.directMatches(matches, target: target)
    }

    @discardableResult private func invokeRuntime(_ args: [String]) async throws -> Any {
        let scope = session.map { ["--session", $0] } ?? []
        let result = try await Command.run(binary, scope + args, options: CommandOptions(timeout: 35))
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

    private static func matchingWindows(_ windows: [[String: Any]], app: String, title: String?) -> [ListedWindow] {
        windows.map(ListedWindow.init).filter { $0.matches(app: app, title: title) }
    }

    static func selectWindow(_ windows: [[String: Any]], app: String, title: String?) throws -> DesktopWindow {
        let matches = Self.matchingWindows(windows, app: app, title: title)
        guard matches.count == 1, let match = matches.first, let id = match.id,
              id.hasPrefix("w-"), let number = UInt32(id.dropFirst(2)), number > 0 else {
            let choices = windows.map { "\($0["id"] ?? "?"): \($0["title"] ?? "")" }.joined(separator: ", ")
            throw Failure("Expected one accessible window for \(app); found \(matches.count). Candidates: \(choices)")
        }
        guard match.accessible else {
            throw Failure("The selected window is not accessible yet. Wait for the app to be ready, then retry. Run showback desktop permissions if this persists.")
        }
        return try DesktopWindow(id: id, title: match.title ?? "", bounds: Box(match.raw["bounds"]), number: number)
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
