import XCTest
@testable import ShowbackCore

final class AssetsTests: XCTestCase {
    func testCorruptAssetCannotPassIntegrityCheck() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("model")
        try Data("hello".utf8).write(to: file)
        XCTAssertNoThrow(try Assets.verify(file, bytes: 5, sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"))
        try Data("wrong".utf8).write(to: file)
        XCTAssertThrowsError(try Assets.verify(file, bytes: 5, sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"))
    }
    func testMissingInstallReceiptIsNotAUsableInstallation() {
        XCTAssertThrowsError(try Assets(root: URL(fileURLWithPath: "/nonexistent/showback-assets")).verifyInstallation())
    }
}
