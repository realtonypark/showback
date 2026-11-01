import Foundation
import CryptoKit

public struct Assets {
    public let root: URL
    public init(root: URL) { self.root = root }

    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static var resourceBundle: Bundle {
        if let base = Bundle.main.resourceURL,
           let bundle = Bundle(url: base.appendingPathComponent("Showback_ShowbackCore.bundle")) { return bundle }
        return Bundle.module
    }

    static func resource(_ name: String, _ ext: String) throws -> URL {
        guard let url = resourceBundle.url(forResource: name, withExtension: ext) else { throw Failure("Missing bundled resource: \(name).\(ext)") }
        return url
    }

    public var catalog: AssetCatalog { get throws { try Self.loadCatalog() } }
    static func loadCatalog() throws -> AssetCatalog {
        try JSONDecoder().decode(AssetCatalog.self, from: Data(contentsOf: resource("assets", "json")))
    }

    public func url(for id: String) throws -> URL {
        guard let asset = try catalog.downloads.first(where: { $0.id == id && ($0.arch == nil || $0.arch == Self.architecture) }) else {
            throw Failure("No installed asset definition for \(id) on \(Self.architecture).")
        }
        if let path = asset.path { return root.appendingPathComponent(path) }
        guard let path = asset.files?.values.first(where: { $0.hasPrefix("bin/") && !$0.contains("helper") }) else {
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

    public func verifyInstallation() throws {
        let marker = root.appendingPathComponent("installed.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { throw Failure("Local model is not installed. Run the Showback installer.") }
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: marker))
        guard receipt.catalog == (try Self.digest(Self.resource("assets", "json"))), receipt.arch == Self.architecture else {
            throw Failure("Installed assets do not match this Showback version. Reinstall Showback.")
        }
        let expected = try catalog.downloads.filter { $0.arch == nil || $0.arch == Self.architecture }
        for asset in expected {
            for path in asset.paths {
                guard let file = receipt.files[path] else { throw Failure("Installed asset is missing: \(path). Reinstall Showback.") }
                try Self.verify(root.appendingPathComponent(path), bytes: file.bytes, sha256: asset.path == nil ? file.sha256 : asset.sha256)
            }
        }
    }

    public func install(progress: (String) -> Void) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("installed.json").path) { try verifyInstallation(); return }
        if fm.fileExists(atPath: root.path), !(try fm.contentsOfDirectory(atPath: root.path)).isEmpty {
            throw Failure("Asset destination is not empty: \(root.path). Use a fresh installation stage.")
        }
        let downloads = try catalog.downloads.filter { $0.arch == nil || $0.arch == Self.architecture }
        let cache = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Showback/Downloads")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        progress("Installing \(try catalog.model) · \(downloads.reduce(0) { $0 + $1.bytes } / 1_000_000) MB download")
        var records: [String: FileReceipt] = [:]
        for (index, asset) in downloads.enumerated() {
            try Task.checkCancellation()
            progress("[\(index + 1)/\(downloads.count)] \(asset.id)")
            let cached = cache.appendingPathComponent(asset.sha256)
            if (try? Self.verify(cached, bytes: asset.bytes, sha256: asset.sha256)) == nil {
                if fm.fileExists(atPath: cached.path) { try fm.removeItem(at: cached) }
                let (temporary, response) = try await URLSession.shared.download(from: asset.url)
                defer { try? fm.removeItem(at: temporary) }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw Failure("Download failed: \(asset.id)") }
                try Self.verify(temporary, bytes: asset.bytes, sha256: asset.sha256)
                try fm.moveItem(at: temporary, to: cached)
            }
            if let path = asset.path {
                let destination = root.appendingPathComponent(path)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: cached, to: destination)
            } else if let files = asset.files {
                for (member, path) in files {
                    let destination = root.appendingPathComponent(path)
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let extracted = try await Command.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xOf", cached.path, member], stdoutFile: destination)
                    guard extracted.status == 0 else { throw Failure("Cannot extract \(asset.id): \(extracted.stderr)") }
                    if path.hasPrefix("bin/") { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path) }
                }
            }
            for path in asset.paths {
                let url = root.appendingPathComponent(path)
                records[path] = try FileReceipt(bytes: url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, sha256: Self.digest(url))
            }
        }
        let receipt = try Receipt(catalog: Self.digest(Self.resource("assets", "json")), arch: Self.architecture, files: records)
        try JSONEncoder().encode(receipt).write(to: root.appendingPathComponent("installed.json"), options: .atomic)
        try verifyInstallation()
        progress("Local assets installed and verified.")
    }
}

public struct AssetCatalog: Decodable {
    public let model: String
    public let voices: [Voice]
    let downloads: [Download]
}

public struct Voice: Decodable {
    public let id: String
    public let name: String
    public let license: String
}

struct Download: Decodable {
    let id: String
    let arch: String?
    let url: URL
    let bytes: Int
    let sha256: String
    let path: String?
    let files: [String: String]?
    var paths: [String] { path.map { [$0] } ?? files.map { Array($0.values) } ?? [] }
}

private struct FileReceipt: Codable { let bytes: Int; let sha256: String }
private struct Receipt: Codable { let catalog: String; let arch: String; let files: [String: FileReceipt] }
