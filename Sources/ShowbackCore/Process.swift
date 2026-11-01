import Foundation

public struct CommandOutput {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum Command {
    public static func run(_ executable: URL, _ arguments: [String], timeout: Double = 30,
                           directory: URL? = nil, environment: [String: String]? = nil) async throws -> CommandOutput {
        let state = CommandState()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("showback-\(UUID().uuidString)")
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                        defer { try? FileManager.default.removeItem(at: folder) }
                        let outputURL = folder.appendingPathComponent("stdout")
                        let errorURL = folder.appendingPathComponent("stderr")
                        try Data().write(to: outputURL)
                        try Data().write(to: errorURL)
                        let output = try FileHandle(forWritingTo: outputURL)
                        let errors = try FileHandle(forWritingTo: errorURL)
                        defer { try? output.close(); try? errors.close() }
                        let process = Process()
                        process.executableURL = executable
                        process.arguments = arguments
                        process.currentDirectoryURL = directory
                        process.environment = environment
                        process.standardOutput = output
                        process.standardError = errors
                        process.standardInput = FileHandle.nullDevice
                        try state.start(process)
                        let deadline = DispatchWorkItem { state.stop("Command timed out after \(timeout) seconds.") }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                        defer { deadline.cancel() }
                        process.waitUntilExit()
                        if let reason = state.reason { throw Failure(reason) }
                        func read(_ url: URL) throws -> String {
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 16_777_216 else { throw Failure("Command output exceeds 16 MiB.") }
                            return String(decoding: try Data(contentsOf: url), as: UTF8.self)
                        }
                        continuation.resume(returning: try CommandOutput(status: process.terminationStatus,
                                                                          stdout: read(outputURL), stderr: read(errorURL)))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { state.stop("Command cancelled.") })
    }
}

private final class CommandState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped: String?
    var reason: String? { lock.lock(); defer { lock.unlock() }; return stopped }
    func start(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if let stopped { throw Failure(stopped) }
        self.process = process
        try process.run()
    }
    func stop(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        guard stopped == nil else { return }
        stopped = message
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
