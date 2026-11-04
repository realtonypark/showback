import XCTest
@testable import ShowbackCore

final class SettingsStoreTests: XCTestCase {
    func testEmptyVoiceCatalogThrowsInsteadOfTrapping() throws {
        let root = try TestFiles.tempDir(self)
        let catalog = AssetCatalog(model: "test", voices: [], downloads: [])
        XCTAssertThrowsError(try SettingsStore(url: root.appendingPathComponent("settings.json")).voice(in: catalog)) { error in
            XCTAssertTrue(error is Failure, "\(type(of: error))")
            XCTAssertTrue(error.localizedDescription.contains("empty"), error.localizedDescription)
        }
    }

    func testMissingFileFallsBackToDefaultVoice() throws {
        let catalog = try Assets.loadCatalog()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        XCTAssertEqual(try SettingsStore(url: missing).voice(in: catalog), catalog.voices[0].id)
    }

    func testSaveThenVoiceRoundTripsSelection() throws {
        let root = try TestFiles.tempDir(self)
        let catalog = try Assets.loadCatalog()
        let voice = catalog.voices.count > 1 ? catalog.voices[1].id : catalog.voices[0].id
        let store = SettingsStore(url: root.appendingPathComponent("settings.json"))
        try store.save(voice: voice, in: catalog)
        XCTAssertEqual(try store.voice(in: catalog), voice)
    }

    func testSaveRejectsUnknownVoice() throws {
        let root = try TestFiles.tempDir(self)
        let catalog = try Assets.loadCatalog()
        XCTAssertThrowsError(try SettingsStore(url: root.appendingPathComponent("settings.json")).save(voice: "unavailable", in: catalog)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unknown voice"), error.localizedDescription)
        }
    }

    func testInvalidSettingsNameFileAndRepairCommand() throws {
        let root = try TestFiles.tempDir(self)
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
