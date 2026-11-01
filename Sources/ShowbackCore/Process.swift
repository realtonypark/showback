import Foundation

public struct CommandOutput {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum Command {
    public static func run(_ executable: URL, _ arguments: [String], timeout: Double = 30,
                           directory: URL? = nil, environment: [String: String]? = nil,
                           stdoutFile: URL? = nil, outputLimit: Int = 16_777_216) async throws -> CommandOutput {
        guard outputLimit > 0 else { throw Failure("Command output limit must be positive.") }
        let state = CommandState()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("showback-\(UUID().uuidString)")
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                        defer { try? FileManager.default.removeItem(at: folder) }
                        let outputURL = stdoutFile ?? folder.appendingPathComponent("stdout")
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
                        process.environment = environment ?? ProcessInfo.processInfo.environment
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
                                Self.drain(pipe, into: file, isRunning: { process.isRunning }, limit: outputLimit, onFailure: state.stop)
                            }
                        }
                        let deadline = DispatchWorkItem { state.stop("Command timed out after \(timeout) seconds.") }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                        defer { deadline.cancel() }
                        process.waitUntilExit()
                        readers.wait()
                        if let reason = state.reason { throw Failure(reason) }
                        func read(_ url: URL) throws -> String {
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= outputLimit else { throw Failure("Command output exceeds \(outputLimit) bytes.") }
                            return String(decoding: try Data(contentsOf: url), as: UTF8.self)
                        }
                        continuation.resume(returning: try CommandOutput(status: process.terminationStatus,
                                                                          stdout: stdoutFile == nil ? read(outputURL) : "", stderr: read(errorURL)))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { state.stop("Command cancelled.") })
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
                do { try file.write(contentsOf: Data(buffer.prefix(count))) }
                catch { onFailure("Cannot save command output: \(error.localizedDescription)"); return }
                total += count
            } else if count == 0 { return }
            else if errno == EINTR { continue }
            else if errno == EAGAIN {
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
