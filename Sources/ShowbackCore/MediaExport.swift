import Foundation
import AVFoundation
import CoreImage

public struct NarrationSegment {
    public let url: URL
    public let start: Double
    public let duration: Double
}

public enum MediaExport {
    public static func render(source: URL, output: URL, narration: [NarrationSegment], pointer: PointerTimeline) async throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure("Export destination already exists: \(output.path)") }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0,
              let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw Failure("Source recording has no usable video.") }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure("Cannot create video composition.")
        }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        if !narration.isEmpty {
            guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw Failure("Cannot create narration track.") }
            for segment in narration {
                guard segment.start >= 0, segment.duration > 0, segment.start + segment.duration <= duration.seconds + 0.1 else {
                    throw Failure("Narration lies outside the recorded timeline. Source media was preserved.")
                }
                let clip = AVURLAsset(url: segment.url)
                guard let track = try await clip.loadTracks(withMediaType: .audio).first else { throw Failure("Missing narration audio: \(segment.url.path)") }
                let length = min(segment.duration, duration.seconds - segment.start)
                try audio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: length, preferredTimescale: 24000)), of: track,
                                          at: CMTime(seconds: segment.start, preferredTimescale: 24000))
            }
        }
        let size = try await sourceVideo.load(.naturalSize)
        let pointerImages = PointerImageCache(timeline: pointer, size: size)
        let filters = try await AVVideoComposition.videoComposition(with: composition, applyingCIFiltersWithHandler: { request in
            let source = request.sourceImage
            if let overlay = pointerImages.image(at: request.compositionTime.seconds) {
                request.finish(with: CIImage(cgImage: overlay).composited(over: source).cropped(to: source.extent), context: nil)
            } else { request.finish(with: source, context: nil) }
        })
        guard let videoComposition = filters.mutableCopy() as? AVMutableVideoComposition,
              let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw Failure("Cannot create MP4 exporter.") }
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        let temporary = output.deletingPathExtension().appendingPathExtension("partial.mp4")
        guard !FileManager.default.fileExists(atPath: temporary.path) else { throw Failure("An incomplete export already exists: \(temporary.path)") }
        try await exporter.export(to: temporary, as: .mp4)
        let result = AVURLAsset(url: temporary)
        let actual = try await result.load(.duration).seconds
        guard abs(actual - duration.seconds) < 0.1 else { throw Failure("Export duration does not match the recording. Source media was preserved.") }
        try FileManager.default.moveItem(at: temporary, to: output)
    }
}
