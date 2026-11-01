import AVFoundation

@MainActor final class AudioPlayback {
    let segment: NarrationSegment
    private let player: AVAudioPlayer?
    private let finishAt: Double
    var usesDeviceClock: Bool { player != nil }

    init(clip: SpeechClip, epoch: Double, mute: Bool) throws {
        let candidate = try AVAudioPlayer(contentsOf: clip.url)
        candidate.volume = mute ? 0 : 1
        var start = ProcessInfo.processInfo.systemUptime
        if candidate.prepareToPlay(), candidate.play(atTime: candidate.deviceCurrentTime + 0.05) {
            start = ProcessInfo.processInfo.systemUptime + 0.05
            player = candidate
        } else {
            guard mute else { throw Failure("Cannot start narration playback.") }
            player = nil
        }
        segment = NarrationSegment(url: clip.url, start: max(0, start - epoch), duration: clip.duration)
        finishAt = start + clip.duration
    }

    func wait() async throws {
        defer { player?.stop() }
        let remaining = max(0, finishAt - ProcessInfo.processInfo.systemUptime)
        try await Task.sleep(nanoseconds: UInt64((remaining + 0.02) * 1_000_000_000))
    }
    func stop() { player?.stop() }
}
