import Foundation

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// A forwarded subprocess exit code. Carries no message: output was already forwarded.
struct ExitStatus: Error {
    let code: Int32
}
