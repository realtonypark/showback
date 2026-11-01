import Foundation

public struct SettingsStore {
    let url: URL
    public init(url: URL = Paths.settings) { self.url = url }

    public func voice(in catalog: AssetCatalog) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return catalog.voices[0].id }
        let fields = try Fields(JSONSerialization.jsonObject(with: Data(contentsOf: url)), keys: ["voice"])
        let value = try fields.string("voice")
        guard catalog.voices.contains(where: { $0.id == value }) else { throw Failure("Saved voice is unavailable. Select a voice in Showback Settings.") }
        return value
    }

    public func save(voice: String, in catalog: AssetCatalog) throws {
        guard catalog.voices.contains(where: { $0.id == voice }) else { throw Failure("Unknown voice: \(voice).") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["voice": voice], options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
}
