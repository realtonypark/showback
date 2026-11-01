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
            let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2400)!
            buffer.frameLength = 2400
            for i in 0..<2400 { buffer.floatChannelData![0][i] = amplitude * sin(Float(i) * 0.05) }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }
        let audible = try write("speech", amplitude: 0.25)
        XCTAssertEqual(try Speech.inspect(audible).duration, 0.1, accuracy: 0.001)
        let silent = try write("silent", amplitude: 0)
        XCTAssertThrowsError(try Speech.inspect(silent))
    }
}
