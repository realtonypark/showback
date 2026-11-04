import AVFoundation
import Foundation

/// Test-only WAV fixture writer: 24 kHz mono with a sine tone.
enum WavFixture {
    static func write(to url: URL, frames: Int = 2400, amplitude: Float = 0.25) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames { buffer.floatChannelData![0][i] = amplitude * sin(Float(i) * 0.05) }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }
}
