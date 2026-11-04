import XCTest
@testable import ShowbackCore

final class RunLockTests: XCTestCase {
    func testDescriptorClosesOnExec() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let lock = try RunLock(url: file)
        defer { lock.release() }
        var expected = stat()
        XCTAssertEqual(stat(file.path, &expected), 0)
        let descriptors = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap(Int32.init)
        let descriptor = try XCTUnwrap(descriptors.first { fd in
            var info = stat()
            return fstat(fd, &info) == 0 && info.st_ino == expected.st_ino && info.st_dev == expected.st_dev
        })
        XCTAssertNotEqual(fcntl(descriptor, F_GETFD) & FD_CLOEXEC, 0)
    }
    func testDirectoryFailureNamesParentPath() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        XCTAssertThrowsError(try RunLock(url: blocker.appendingPathComponent("run.lock"))) { error in
            XCTAssertTrue(error is Failure, "\(type(of: error))")
            XCTAssertTrue(error.localizedDescription.contains(blocker.path), error.localizedDescription)
        }
    }
    func testSecondRunCannotTakeDesktopWhileFirstOwnsIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var first: RunLock? = try RunLock(url: file)
        XCTAssertThrowsError(try RunLock(url: file))
        first?.release()
        first = nil
        XCTAssertNoThrow(try RunLock(url: file))
    }
}
