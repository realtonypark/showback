import Foundation

struct CommandOutput {
    let status: Int32
    let stdout: String
    let stderr: String
}

struct CommandOptions {
    var timeout: Double = 30
    var directory: URL?
    var environment: [String: String]?
    /// When set, stdout streams here byte-for-byte and `CommandOutput.stdout` is empty; read the file instead.
    var stdoutFile: URL?
    var outputLimit: Int = 16_777_216
}

enum Command {
    /// Runs a command, capturing stdout/stderr as text. When `options.stdoutFile` is set, stdout streams to
    /// that file and the returned `stdout` is empty.
    /// - Throws: `Failure` for timeouts, launch failures, or output over the limit; `CancellationError` when cancelled.
    static func run(_ executable: URL, _ arguments: [String], options: CommandOptions = CommandOptions()) async throws -> CommandOutput {
        guard options.outputLimit > 0 else { throw Failure("Command output limit must be positive.") }
        let state = CommandState()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("showback-\(UUID().uuidString)")
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                        defer { try? FileManager.default.removeItem(at: folder) }
                        let outputURL = options.stdoutFile ?? folder.appendingPathComponent("stdout")
                        let errorURL = folder.appendingPathComponent("stderr")
                        try Data().write(to: outputURL)
                        try Data().write(to: errorURL)
                        let output = try FileHandle(forWritingTo: outputURL)
                        let errors = try FileHandle(forWritingTo: errorURL)
                        defer { try? output.close(); try? errors.close() }
                        let process = Process()
                        process.executableURL = executable
                        process.arguments = arguments
                        process.currentDirectoryURL = options.directory
                        process.environment = options.environment ?? ProcessInfo.processInfo.environment
                        let stdout = Pipe(), stderr = Pipe()
                        process.standardOutput = stdout
                        process.standardError = stderr
                        process.standardInput = FileHandle.nullDevice
                        try state.start(process)
                        try? stdout.fileHandleForWriting.close()
                        try? stderr.fileHandleForWriting.close()
                        let readers = DispatchGroup()
                        for (pipe, file) in [(stdout, output), (stderr, errors)] {
                            readers.enter()
                            DispatchQueue.global(qos: .userInitiated).async {
                                defer { readers.leave() }
                                Self.drain(pipe, into: file, isRunning: { process.isRunning }, limit: options.outputLimit, onFailure: state.stop)
                            }
                        }
                        let deadline = DispatchWorkItem { state.stop("Command timed out after \(options.timeout) seconds.") }
                        DispatchQueue.global().asyncAfter(deadline: .now() + options.timeout, execute: deadline)
                        defer { deadline.cancel() }
                        process.waitUntilExit()
                        readers.wait()
                        if state.cancelled { throw CancellationError() }
                        if let reason = state.reason { throw Failure(reason) }
                        func read(_ url: URL) throws -> String {
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= options.outputLimit else { throw Failure("Command output exceeds \(options.outputLimit) bytes.") }
                            return String(decoding: try Data(contentsOf: url), as: UTF8.self)
                        }
                        continuation.resume(returning: try CommandOutput(status: process.terminationStatus,
                                                                          stdout: options.stdoutFile == nil ? read(outputURL) : "", stderr: read(errorURL)))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { state.cancel() })
    }

    static func drain(_ pipe: Pipe, into file: FileHandle, isRunning: () -> Bool, limit: Int, onFailure: (String) -> Void) {
        let input = pipe.fileHandleForReading
        defer { try? input.close() }
        let descriptor = input.fileDescriptor
        guard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0 else {
            onFailure("Cannot read command output."); return
        }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var total = 0
        while true {
            let wasRunning = isRunning()
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard count <= limit - total else { onFailure("Command output exceeds \(limit) bytes."); return }
                do {
                    try file.write(contentsOf: Data(buffer.prefix(count)))
                } catch {
                    onFailure("Cannot save command output: \(error.localizedDescription)")
                    return
                }
                total += count
            } else if count == 0 {
                return
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN {
                // Drain once after known exit before abandoning a pipe retained by descendants.
                guard wasRunning else { return }
                usleep(10_000)
            } else { onFailure("Cannot read command output."); return }
        }
    }

}

private final class CommandState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped: String?
    private var wasCancelled = false
    var reason: String? { lock.lock(); defer { lock.unlock() }; return stopped }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return wasCancelled }
    func start(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if let stopped {
            if wasCancelled { throw CancellationError() }
            throw Failure(stopped)
        }
        self.process = process
        do {
            try process.run()
        } catch {
            throw Failure("Cannot launch \(process.executableURL?.lastPathComponent ?? "command"): \(error.localizedDescription)")
        }
    }
    func stop(_ message: String) { halt(message, cancelled: false) }
    func cancel() { halt("Command cancelled.", cancelled: true) }
    private func halt(_ message: String, cancelled: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard stopped == nil else { return }
        stopped = message
        wasCancelled = cancelled
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
