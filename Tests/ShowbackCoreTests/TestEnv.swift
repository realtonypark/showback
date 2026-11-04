import Foundation

/// Shared environment swapping for tests that read configuration from the environment.
enum TestEnv {
    static func withValue(_ value: String?, for key: String, _ body: () throws -> Void) rethrows {
        let saved = getenv(key).map { String(cString: $0) }
        if let value { setenv(key, value, 1) } else { unsetenv(key) }
        defer {
            if let saved { setenv(key, saved, 1) } else { unsetenv(key) }
        }
        try body()
    }
}
