import Foundation

struct SettingsStore {
    let url: URL
    init(url: URL = Paths.settings) { self.url = url }

    /// - Throws: `Failure` for an unavailable saved voice or unreadable settings.
    func voice(in catalog: AssetCatalog) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            guard let first = catalog.voices.first else { throw Failure("Installed voice catalog is empty. Reinstall Showback.") }
            return first.id
        }
        do {
            let fields = try Fields(JSONSerialization.jsonObject(with: Data(contentsOf: url)), keys: ["voice"])
            let value = try fields.string("voice")
            guard catalog.voices.contains(where: { $0.id == value }) else { throw Failure("Saved voice is unavailable.") }
            return value
        } catch {
            throw Failure("Cannot load settings at \(url.path): \(error.localizedDescription) Select a voice with showback settings.")
        }
    }

    /// - Throws: `Failure` for an unknown voice; file errors when settings cannot be written.
    func save(voice: String, in catalog: AssetCatalog) throws {
        guard catalog.voices.contains(where: { $0.id == voice }) else { throw Failure("Unknown voice: \(voice).") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["voice": voice], options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
}
