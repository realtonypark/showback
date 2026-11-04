import Foundation

final class RunLock {
    private var descriptor: Int32 = -1
    /// - Throws: `Failure` when the lock cannot be created or another run owns it.
    init(url: URL) throws {
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw Failure("Cannot create the run lock directory at \(parent.path): \(error.localizedDescription)")
        }
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure("Cannot create the desktop run lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw Failure("Another Showback run owns this desktop. Stop it before starting another.")
        }
        self.descriptor = descriptor
    }
    func release() {
        if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 }
    }
    deinit { release() }
}
