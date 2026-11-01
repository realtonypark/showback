import Foundation
import AVFoundation

public struct SpeechClip {
    public let url: URL
    public let duration: Double
}

public struct Speech {
    public let assets: Assets
    public init(assets: Assets) { self.assets = assets }
    public func prepare(_ scenes: [Scene], voice: String, in folder: URL,
                        progress: (String) -> Void) async throws -> [Int: SpeechClip] {
        try assets.verifyInstallation()
        guard try assets.catalog.voices.contains(where: { $0.id == voice }) else { throw Failure("Unknown voice: \(voice).") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = try String(contentsOf: Assets.resource("speech", "yaml"), encoding: .utf8)
            .replacingOccurrences(of: "__MODEL_FILE__", with: String(decoding: JSONEncoder().encode(assets.url(for: "model").path), as: UTF8.self))
            .replacingOccurrences(of: "__TOKENIZER_FILE__", with: String(decoding: JSONEncoder().encode(assets.url(for: "tokenizer").path), as: UTF8.self))
        let configURL = folder.appendingPathComponent("config.yaml")
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        var clips: [Int: SpeechClip] = [:]
        for (index, scene) in scenes.enumerated() {
            try Task.checkCancellation()
            guard let text = scene.say else { continue }
            progress("Preparing narration \(index + 1)/\(scenes.count)")
            let output = folder.appendingPathComponent(String(format: "scene-%02d.wav", index + 1))
            let result = try await Command.run(assets.url(for: "speech-runtime"), ["generate", "--config", configURL.path,
                "--voice", assets.url(for: "voice-\(voice)").path, "--text", text, "--output-path", output.path],
                timeout: 300, directory: assets.root, environment: environment)
            guard result.status == 0 else { throw Failure("Narration failed for scene \(index + 1): \(result.stderr)") }
            clips[index] = try Self.inspect(output)
        }
        return clips
    }

    static func inspect(_ url: URL) throws -> SpeechClip {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite, duration > 0, format.channelCount == 1, format.sampleRate == 24000,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000) else {
            throw Failure("Narration is not valid 24 kHz mono audio: \(url.lastPathComponent).")
        }
        guard duration <= 900 else { throw Failure("Narration exceeds the 900 seconds limit: \(url.lastPathComponent).") }
        var audible = false
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?[0] else { throw Failure("Cannot read narration samples.") }
            for index in 0..<Int(buffer.frameLength) {
                guard channel[index].isFinite else { throw Failure("Narration contains invalid samples.") }
                audible = audible || abs(channel[index]) > 0.00001
            }
        }
        guard audible else { throw Failure("Narration contains only silence: \(url.lastPathComponent).") }
        return SpeechClip(url: url, duration: duration)
    }
}
