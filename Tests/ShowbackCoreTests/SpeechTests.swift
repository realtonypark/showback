import XCTest
import AVFoundation
@testable import ShowbackCore

final class SpeechTests: XCTestCase {
    func testOverlongValidAudioNamesDurationLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes: UInt32 = 901 * 24000 * 2
        var header = Data("RIFF".utf8)
        func number(_ n: UInt32) { var value = n.littleEndian; withUnsafeBytes(of: &value) { header.append(contentsOf: $0) } }
        number(bytes + 36); header.append(Data("WAVEfmt ".utf8)); number(16)
        header.append(contentsOf: [1, 0, 1, 0]); number(24000); number(48000)
        header.append(contentsOf: [2, 0, 16, 0]); header.append(Data("data".utf8)); number(bytes)
        try header.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes) + 44); try handle.close()
        XCTAssertThrowsError(try Speech.inspect(url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("900 seconds"), error.localizedDescription)
        }
    }
    func testAudioInspectionRejectsSilenceAndReadsActualDuration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ name: String, amplitude: Float) throws -> URL {
            let url = folder.appendingPathComponent(name + ".wav")
            try WavFixture.write(to: url, amplitude: amplitude)
            return url
        }
        let audible = try write("speech", amplitude: 0.25)
        XCTAssertEqual(try Speech.inspect(audible).duration, 0.1, accuracy: 0.001)
        let silent = try write("silent", amplitude: 0)
        XCTAssertThrowsError(try Speech.inspect(silent))
    }

    private func fakeRuntime(root: URL, script: String) throws -> URL {
        let runtime = try Assets(root: root).url(for: "speech-runtime")
        try FileManager.default.createDirectory(at: runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: runtime, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        return runtime
    }

    private func scene(say: String?) -> Scene {
        Scene(say: say, actions: [], expect: nil, absent: nil, app: nil, windowTitle: nil)
    }

    func testSynthesizeWritesClipsForSpokenScenesOnly() async throws {
        let root = try TestFiles.tempDir(self)
        let catalog = try Assets.loadCatalog()
        let voice = catalog.voices[0].id
        let sample = root.appendingPathComponent("sample.wav")
        try WavFixture.write(to: sample)
        let log = root.appendingPathComponent("calls")
        let runtime = try fakeRuntime(root: root, script: """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(log.path)'
        out=""; prev=""
        for arg in "$@"; do
          if [ "$prev" = --output-path ]; then out="$arg"; fi
          prev="$arg"
        done
        cp '\(sample.path)' "$out"
        """)
        let folder = root.appendingPathComponent("narration")
        let clips = try await Speech.synthesize([scene(say: "Hello"), scene(say: nil)], voice: voice,
                                                assets: Assets(root: root), in: folder) { _ in }
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0]?.duration ?? -1, 0.1, accuracy: 0.01)
        XCTAssertNil(clips[1])
        let config = try String(contentsOf: folder.appendingPathComponent("config.yaml"), encoding: .utf8)
        XCTAssertFalse(config.contains("__MODEL_FILE__"), config)
        XCTAssertFalse(config.contains("__TOKENIZER_FILE__"), config)
        XCTAssertTrue(config.contains("model.safetensors"), config)
        XCTAssertTrue(config.contains("tokenizer.model"), config)
        let calls = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(calls.contains("--voice"), calls)
        XCTAssertTrue(calls.contains("\(voice).safetensors"), calls)
    }

    func testSynthesizeRejectsUnknownVoice() async throws {
        let root = try TestFiles.tempDir(self)
        let catalog = try Assets.loadCatalog()
        do {
            _ = try await Speech.synthesize([scene(say: "Hello")], voice: "nope",
                                            assets: Assets(root: root), in: root.appendingPathComponent("narration")) { _ in }
            XCTFail("expected unknown voice to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Unknown voice"), error.localizedDescription)
        }
    }

    func testSynthesizeMapsRuntimeFailure() async throws {
        let root = try TestFiles.tempDir(self)
        let catalog = try Assets.loadCatalog()
        _ = try fakeRuntime(root: root, script: "#!/bin/sh\necho boom >&2\nexit 3\n")
        do {
            _ = try await Speech.synthesize([scene(say: "Hello")], voice: catalog.voices[0].id,
                                            assets: Assets(root: root), in: root.appendingPathComponent("narration")) { _ in }
            XCTFail("expected runtime failure to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Narration failed for scene 1"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("boom"), error.localizedDescription)
        }
    }
}
