import XCTest
import AVFoundation
@testable import ShowbackCore

final class MediaTests: XCTestCase {
    func testCaptureFailureDoesNotPretendOutputHasFinalized() {
        let state = RecordingState()
        state.fail("Window closed")
        XCTAssertFalse(state.finished)
        XCTAssertEqual(state.problem, "Window closed")
        state.finish()
        XCTAssertTrue(state.finished)
        XCTAssertEqual(state.problem, "Window closed")
    }

    private func writeStaticMovie(to movie: URL) async throws {
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180
        ])
        writer.add(input)
        guard writer.startWriting() else {
            throw XCTSkip("h264 encoder unavailable: \(writer.error?.localizedDescription ?? "unknown error")")
        }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<20 {
            let deadline = ProcessInfo.processInfo.systemUptime + 15
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    let detail = writer.error?.localizedDescription ?? String(describing: writer.status)
                    throw Failure("Fixture writer did not become ready: \(detail)")
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer), kCVReturnSuccess)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), 40, CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            XCTAssertTrue(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func writeVoiceTone(to audio: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000)!
        buffer.frameLength = 24000
        for i in 0..<24000 { buffer.floatChannelData![0][i] = sin(Float(i) * 0.1) * 0.2 }
        let file = try AVAudioFile(forWriting: audio, settings: format.settings)
        try file.write(from: buffer)
    }

    func testExportIncludesNarrationAndVisiblePresentationOnStaticVideo() async throws {
        let root = try TestFiles.tempDir(self)
        let movie = root.appendingPathComponent("source.mp4")
        try await writeStaticMovie(to: movie)
        let audio = root.appendingPathComponent("voice.wav")
        try writeVoiceTone(to: audio)
        var timeline = PointerTimeline()
        try timeline.point(at: 0.2, target: Box(x: 80, y: 40, width: 40, height: 20),
                               viewport: Box(x: 0, y: 0, width: 320, height: 180))
        let output = root.appendingPathComponent("demo.mp4")
        let narration = [NarrationSegment(url: audio, start: 0.5, duration: 1)]
        try await MediaExport.render(source: movie, output: output, narration: narration, pointer: timeline)
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.1)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        let range = try await track.load(.timeRange)
        XCTAssertEqual(range.start.seconds, 0, accuracy: 0.05)
        XCTAssertEqual(range.end.seconds, 1.5, accuracy: 0.05)
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(decoded)
        XCTAssertTrue(reader.startReading())
        var leading: [Float] = [], spoken: [Float] = []
        while let sample = decoded.copyNextSampleBuffer() {
            let block = try XCTUnwrap(sample.dataBuffer)
            var bytes = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size)
            let copied = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            XCTAssertEqual(copied, kCMBlockBufferNoErr)
            for (index, value) in bytes.enumerated() {
                let time = sample.presentationTimeStamp.seconds + Double(index) / 24000
                if (0.1..<0.4).contains(time) { leading.append(value) }
                if (0.6..<1.4).contains(time) { spoken.append(value) }
            }
        }
        XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "")
        XCTAssertGreaterThan(leading.count, 6000)
        XCTAssertGreaterThan(spoken.count, 18000)
        func rms(_ values: [Float]) -> Double {
            sqrt(values.reduce(0) { $0 + Double($1 * $1) } / Double(max(1, values.count)))
        }
        XCTAssertLessThan(rms(leading), 0.005)
        XCTAssertEqual(rms(spoken), 0.2 / sqrt(2), accuracy: 0.02)
        let crossings = zip(spoken, spoken.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        XCTAssertEqual(Double(crossings) / (Double(spoken.count) / 24000), 24000 * 0.1 / (2 * .pi), accuracy: 5)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        let context = CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 1280,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 180))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        let whitePixels = (0..<(320 * 180)).filter {
            pixels[$0 * 4] > 200 && pixels[$0 * 4 + 1] > 200 && pixels[$0 * 4 + 2] > 200
        }.count
        XCTAssertGreaterThan(whitePixels, 100)
    }
}
