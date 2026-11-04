import XCTest
import AVFoundation
@testable import ShowbackCore

final class AudioPlaybackTests: XCTestCase {
    private func fixtureClip() throws -> (url: URL, duration: Double) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try WavFixture.write(to: url)
        return (url, 0.1)
    }

    @MainActor
    func testMuteModeSegmentsShortClipWithPassThroughDuration() throws {
        let (url, duration) = try fixtureClip()
        defer { try? FileManager.default.removeItem(at: url) }
        let epoch = ProcessInfo.processInfo.systemUptime
        let playback = try AudioPlayback(clip: SpeechClip(url: url, duration: duration), epoch: epoch, mute: true)
        XCTAssertEqual(playback.segment.url, url)
        XCTAssertEqual(playback.segment.duration, duration)
        XCTAssertGreaterThanOrEqual(playback.segment.start, 0)
        XCTAssertLessThan(playback.segment.start, 1.0)
    }

    @MainActor
    func testWaitReturnsAfterSegmentFinishes() async throws {
        let (url, duration) = try fixtureClip()
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = try AudioPlayback(clip: SpeechClip(url: url, duration: duration),
                                         epoch: ProcessInfo.processInfo.systemUptime, mute: true)
        let start = ProcessInfo.processInfo.systemUptime
        try await playback.wait()
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 5.0)
    }
}
