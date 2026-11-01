import Foundation

public enum CLI {
    public static func perform(_ arguments: [String]) async throws -> Bool {
        guard let command = arguments.first else { print(help); return true }
        switch command {
        case "--help", "help", "-h": print(help)
        case "--version": print("Showback 0.1.0")
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

    --mute records narration without playing it through speakers.
    """
}
