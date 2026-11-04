import Foundation
import XCTest

/// Shared test scratch space: unique temp directories removed in teardown.
enum TestFiles {
    static func tempDir(_ test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
