import Foundation
@testable import ShowbackCore

/// Shared fake agent-desktop binary for headless tests.
enum FakeDesktop {
    static let window: [String: Any] = ["id": "w-1", "title": "Account", "app_name": "Example", "accessible": true,
                                        "bounds": ["x": -100.0, "y": 10.0, "width": 800.0, "height": 600.0]]

    static func windows() throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "data": [window]]), as: UTF8.self)
    }

    static func make(root: URL, log: URL? = nil, sessionFile: String = "s.json", branches: String) throws -> Desktop {
        let binary = root.appendingPathComponent("desktop")
        var script = """
        #!/bin/sh
        if [ "$1" = --session ]; then shift 2; fi

        """
        if let log { script += "printf '%s\\n' \"$*\" >> '\(log.path)'\n" }
        script += """
        case "$1 $2" in
        \(branches)
          list-windows*) printf '%s' '\(try windows())' ;;
          *) printf '%s' '{"ok":true,"data":{}}' ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return Desktop(binary: binary, app: "Example", title: "Account", sessionFile: root.appendingPathComponent(sessionFile))
    }
}
