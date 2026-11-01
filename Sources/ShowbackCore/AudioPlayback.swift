import AVFoundation

@MainActor final class AudioPlayback {
    let segment: NarrationSegment
    private let player: AVAudioPlayer?
    private let finishAt: Double

    init(clip: SpeechClip, epoch: Double, mute: Bool) throws {
        let start: Double
        if mute {
            player = nil
            start = ProcessInfo.processInfo.systemUptime
        } else {
            let player = try AVAudioPlayer(contentsOf: clip.url)
            guard player.prepareToPlay() else { throw Failure("Cannot prepare narration playback.") }
            let deviceStart = player.deviceCurrentTime + 0.05
            start = ProcessInfo.processInfo.systemUptime + 0.05
            guard player.play(atTime: deviceStart) else { throw Failure("Cannot start narration playback.") }
            self.player = player
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
