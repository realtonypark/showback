import XCTest
import AVFoundation
@testable import ShowbackCore

final class SpeechTests: XCTestCase {
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
