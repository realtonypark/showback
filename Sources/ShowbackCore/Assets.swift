import Foundation
import CryptoKit

struct Assets {
    let root: URL
    init(root: URL) { self.root = root }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static func resource(_ name: String, _ ext: String) throws -> URL {
        let bundle: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let base = Bundle.main.resourceURL,
                  let installed = Bundle(url: base.appendingPathComponent("Showback_ShowbackCore.bundle")) else {
                throw Failure("Installed Showback resources are missing. Reinstall Showback.")
            }
            bundle = installed
        } else { bundle = Bundle.module }
        guard let url = bundle.url(forResource: name, withExtension: ext) else { throw Failure("Missing bundled resource: \(name).\(ext)") }
        return url
    }

    static func loadCatalog() throws -> AssetCatalog {
        try JSONDecoder().decode(AssetCatalog.self, from: Data(contentsOf: resource("assets", "json")))
    }

    private static func installs(_ download: Download) -> Bool {
        download.arch == nil || download.arch == Self.architecture
    }

    /// - Throws: `Failure` when no asset definition matches the id, or the asset has no executable.
    func url(for id: String) throws -> URL {
        guard let asset = try Self.loadCatalog().downloads.first(where: { $0.id == id && Self.installs($0) }) else {
            throw Failure("No installed asset definition for \(id) on \(Self.architecture).")
        }
        if let path = asset.path { return root.appendingPathComponent(path) }
        guard let path = asset.files?.values.first(where: { $0.path.hasPrefix("bin/") && !$0.path.contains("helper") })?.path else {
            throw Failure("No executable in \(id).")
        }
        return root.appendingPathComponent(path)
    }

    static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ url: URL, bytes: Int, sha256: String) throws {
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes,
              try digest(url) == sha256 else { throw Failure("Integrity check failed for \(url.lastPathComponent). Reinstall Showback.") }
    }

    /// - Throws: `Failure` when assets are missing, version-mismatched, or fail integrity checks.
    func verifyInstallation() throws {
        let marker = root.appendingPathComponent("installed.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { throw Failure("Local model is not installed. Run the Showback installer.") }
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: marker))
        guard receipt.catalog == (try Self.digest(Self.resource("assets", "json"))), receipt.arch == Self.architecture else {
            throw Failure("Installed assets do not match this Showback version. Reinstall Showback.")
        }
        let expected = try Self.loadCatalog().downloads.filter(Self.installs)
        for asset in expected {
            for file in asset.installedFiles {
                guard FileManager.default.fileExists(atPath: root.appendingPathComponent(file.path).path) else {
                    throw Failure("Installed asset is missing: \(file.path). Reinstall Showback.")
                }
                try Self.verify(root.appendingPathComponent(file.path), bytes: file.bytes, sha256: file.sha256)
            }
        }
    }

    /// - Throws: `Failure` for a non-empty destination or download, extraction, or verification errors; `CancellationError` when cancelled.
    func install(progress: (String) -> Void) async throws {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("installed.json").path) { try verifyInstallation(); return }
        if FileManager.default.fileExists(atPath: root.path), !(try FileManager.default.contentsOfDirectory(atPath: root.path)).isEmpty {
            throw Failure("Asset destination is not empty: \(root.path). Use a fresh installation stage.")
        }
        let downloads = try Self.loadCatalog().downloads.filter(Self.installs)
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Showback/Downloads")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        progress("Installing \(try Self.loadCatalog().model) · \(downloads.reduce(0) { $0 + $1.bytes } / 1_000_000) MB download")
        for (index, asset) in downloads.enumerated() {
            try Task.checkCancellation()
            progress("[\(index + 1)/\(downloads.count)] \(asset.id)")
            let cached = cache.appendingPathComponent(asset.sha256)
            if (try? Self.verify(cached, bytes: asset.bytes, sha256: asset.sha256)) == nil {
                if FileManager.default.fileExists(atPath: cached.path) { try FileManager.default.removeItem(at: cached) }
                let (temporary, response) = try await URLSession.shared.download(from: asset.url)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw Failure("Download failed: \(asset.id)") }
                try Self.verify(temporary, bytes: asset.bytes, sha256: asset.sha256)
                try FileManager.default.moveItem(at: temporary, to: cached)
            }
            if let path = asset.path {
                let destination = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: cached, to: destination)
            } else if let files = asset.files {
                for (member, file) in files {
                    let destination = root.appendingPathComponent(file.path)
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let extracted = try await Command.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xOf", cached.path, member], options: CommandOptions(stdoutFile: destination, outputLimit: file.bytes))
                    guard extracted.status == 0 else { throw Failure("Cannot extract \(asset.id): \(extracted.stderr)") }
                    if file.path.hasPrefix("bin/") { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path) }
                }
            }
        }
        let receipt = try Receipt(catalog: Self.digest(Self.resource("assets", "json")), arch: Self.architecture)
        try JSONEncoder().encode(receipt).write(to: root.appendingPathComponent("installed.json"), options: .atomic)
        try verifyInstallation()
        progress("Local assets installed and verified.")
    }
}

struct AssetCatalog: Decodable {
    let model: String
    let voices: [Voice]
    let downloads: [Download]
}

struct Voice: Decodable {
    let id: String
    let name: String
    let license: String
}

struct Download: Decodable {
    let id: String
    let arch: String?
    let url: URL
    let bytes: Int
    let sha256: String
    let path: String?
    let files: [String: InstalledFile]?
    var installedFiles: [InstalledFile] {
        path.map { [InstalledFile(path: $0, bytes: bytes, sha256: sha256)] } ?? files.map { Array($0.values) } ?? []
    }
}

struct InstalledFile: Decodable { let path: String; let bytes: Int; let sha256: String }
private struct Receipt: Codable { let catalog: String; let arch: String }
