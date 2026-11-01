import XCTest
@testable import ShowbackCore

final class SettingsStoreTests: XCTestCase {
    func testInvalidSettingsNameFileAndRepairCommand() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("settings.json")
        let catalog = try Assets.loadCatalog()
        for text in ["not json", #"{"voice":"alba","extra":true}"#, #"{"voice":"unavailable"}"#] {
            try text.write(to: url, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try SettingsStore(url: url).voice(in: catalog)) { error in
                XCTAssertTrue(error.localizedDescription.contains(url.path), error.localizedDescription)
                XCTAssertTrue(error.localizedDescription.contains("showback settings"), error.localizedDescription)
            }
        }
    }
}
