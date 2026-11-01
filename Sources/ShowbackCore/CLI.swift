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
            guard arguments.count == 2 else { throw Failure("Usage: showback validate SCRIPT.json") }
            let script = try DemoScript.load(URL(fileURLWithPath: arguments[1]))
            print("Valid: \(script.title) · \(script.scenes.count) scenes")
        case "install-assets":
            guard arguments.count == 2, arguments[1].hasPrefix("/") else { throw Failure("Usage: showback install-assets /absolute/staging/Assets") }
            try await Assets(root: URL(fileURLWithPath: arguments[1])).install { print($0); fflush(stdout) }
        case "doctor":
            let assets = try Paths.assets()
            try assets.verifyInstallation()
            print("Model: \(try assets.catalog.model)")
            print("Voice: \(try SettingsStore().voice(in: assets.catalog))")
            print("Assets: \(assets.root.path)")
            let result = try await Command.run(assets.url(for: "desktop-runtime"), ["status"])
            guard result.status == 0 else { throw Failure("Desktop status exited \(result.status): \(result.stderr)\(result.stdout)") }
            print(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return false
        }
        return true
    }

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
