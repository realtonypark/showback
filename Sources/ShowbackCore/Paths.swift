import Foundation

public enum Paths {
    public static func assets() throws -> Assets {
        if let path = ProcessInfo.processInfo.environment["SHOWBACK_ASSETS"] {
            guard path.hasPrefix("/") else { throw Failure("SHOWBACK_ASSETS must be an absolute path.") }
            return Assets(root: URL(fileURLWithPath: path))
        }
        guard Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL else {
            throw Failure("Use the installed Showback CLI, or set SHOWBACK_ASSETS for development.")
        }
        return Assets(root: resources.appendingPathComponent("Assets"))
    }

    public static var settings: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Showback/settings.json")
    }
    public static var recordings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Showback")
    }
}
