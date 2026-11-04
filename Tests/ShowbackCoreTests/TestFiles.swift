import CoreGraphics
import Foundation
import XCTest
@testable import ShowbackCore

/// Shared test scratch space: unique temp directories removed in teardown.
enum TestFiles {
    static func tempDir(_ test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// First onscreen window with nonzero size, for tests that need live window state.
    static func onscreenWindow() -> (number: UInt32, box: Box)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]])?.first(where: {
            ($0[kCGWindowNumber as String] as? UInt32).map { $0 > 0 } == true
        }),
              let number = info[kCGWindowNumber as String] as? UInt32,
              let raw = info[kCGWindowBounds as String] as? [String: Any],
              let x = raw["X"] as? Double, let y = raw["Y"] as? Double,
              let width = raw["Width"] as? Double, let height = raw["Height"] as? Double, width > 0, height > 0 else {
            return nil
        }
        return (number, Box(x: x, y: y, width: width, height: height))
    }
}
