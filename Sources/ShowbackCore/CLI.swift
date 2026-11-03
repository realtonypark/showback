import Foundation

public struct RunOptions {
    public let script: URL
    public let output: URL
    public let liveOnly: Bool
    public let mute: Bool
    static func parse(_ arguments: [String]) throws -> RunOptions {
        guard let path = arguments.first, !path.hasPrefix("-") else { throw Failure("Usage: showback run SCRIPT.json [--live-only] [--mute] [--out BUNDLE.showback]") }
        var liveOnly = false, mute = false
        var output: URL?
        var seen = Set<String>()
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            guard seen.insert(flag).inserted else { throw Failure("Repeated option: \(flag)") }
            switch flag {
            case "--live-only": liveOnly = true
            case "--mute": mute = true
            case "--out":
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--") else { throw Failure("--out requires a bundle path.") }
                output = URL(fileURLWithPath: arguments[index]).standardizedFileURL
            default: throw Failure("Unknown run option: \(flag)")
            }
            index += 1
        }
        let name = "showback-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).showback"
        return RunOptions(script: URL(fileURLWithPath: path).standardizedFileURL, output: output ?? Paths.recordings.appendingPathComponent(name),
                          liveOnly: liveOnly, mute: mute)
    }
}

public enum CLI {
    public static func perform(_ arguments: [String]) async throws -> Bool {
        guard let command = arguments.first else { print(help); return true }
        switch command {
        case "--help", "help", "-h": print(help)
        case "--version":
            let version = try String(contentsOf: Assets.resource("version", "txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            print("Showback \(version)")
        case "desktop":
            let assets = try Paths.assets()
            try assets.verifyInstallation()
            let args = arguments.count > 1 ? Array(arguments.dropFirst()) : ["--help"]
            let result = try await Command.run(assets.url(for: "desktop-runtime"), args, timeout: 300)
            FileHandle.standardOutput.write(Data(result.stdout.utf8))
            FileHandle.standardError.write(Data(result.stderr.utf8))
            if result.status != 0 { exit(result.status) }
        case "validate":
            if arguments.count == 2, ["--help", "-h"].contains(arguments[1]) { print(validateHelp); return true }
            guard arguments.count == 2 else { throw Failure("Usage: showback validate SCRIPT.json") }
            let script = try DemoScript.load(URL(fileURLWithPath: arguments[1]))
            print("Valid: \(script.title) · \(script.scenes.count) scenes")
            print("Schema only; application state and targets have not been checked.")
        case "install-assets":
            guard arguments.count == 2, arguments[1].hasPrefix("/") else { throw Failure("Usage: showback install-assets /absolute/staging/Assets") }
            try await Assets(root: URL(fileURLWithPath: arguments[1])).install { print($0); fflush(stdout) }
        case "doctor":
            let assets = try Paths.assets()
            try assets.verifyInstallation()
            print("Model: \(try assets.catalog.model)")
            print("Voice: \(try SettingsStore().voice(in: assets.catalog))")
            print("Assets: \(assets.root.path)")
            if Bundle.main.bundleURL.pathExtension == "app" {
                let skill = skillURL(forApp: Bundle.main.bundleURL)
                try validateSkill(at: skill)
                print("Skill: \(skill.path)")
            }
            let result = try await Command.run(assets.url(for: "desktop-runtime"), ["status"])
            guard result.status == 0 else { throw Failure("Desktop status exited \(result.status): \(result.stderr)\(result.stdout)") }
            let status = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let permissions = permissionSummary(status) {
                print("Permissions: \(permissions)")
                if !requiredGrantsReady(status) {
                    print("Next: showback desktop permissions --guide")
                }
            }
            print("Desktop: \(status)")
        default: return false
        }
        return true
    }

    static func skillURL(forApp app: URL) -> URL {
        app.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".agents/skills/showback/SKILL.md")
    }

    static func validateSkill(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure("Agent skill is not installed at \(url.path). Reinstall Showback.")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.hasPrefix("---\nname: showback\n") else {
            throw Failure("Agent skill is invalid at \(url.path). Reinstall Showback.")
        }
    }

    static func permissionsPayload(_ output: String) -> [String: Any]? {
        guard let data = output.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = response["data"] as? [String: Any],
              let permissions = payload["permissions"] as? [String: Any] else { return nil }
        return permissions
    }

    static func requiredGrantsReady(_ output: String) -> Bool {
        guard let permissions = permissionsPayload(output) else { return false }
        return ["accessibility", "screen_recording"].allSatisfy {
            (permissions[$0] as? [String: Any])?["state"] as? String == "granted"
        }
    }

    static func permissionSummary(_ output: String) -> String? {
        guard let permissions = permissionsPayload(output) else { return nil }
        return [("accessibility", "Accessibility"), ("automation", "Automation"), ("screen_recording", "Screen recording")]
            .compactMap { key, label in
                ((permissions[key] as? [String: Any])?["state"] as? String).map { "\(label) \($0)" }
            }
            .joined(separator: ", ")
    }

    static let validateHelp = "Usage: showback validate SCRIPT.json"

    public static let help = """
    Showback

      showback run SCRIPT.json [--live-only] [--mute] [--out BUNDLE.showback]
      showback validate SCRIPT.json
      showback settings
      showback doctor
      showback desktop <agent-desktop arguments>

    --mute records narration without playing it through speakers.
    """
}
