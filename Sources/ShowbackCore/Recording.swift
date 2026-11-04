import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreImage

struct CaptureFailure: LocalizedError {
    let message: String
    init(message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Capture mode: a fixed display or a followed window. Constructed once per run.
@MainActor enum CaptureTarget {
    case display(id: UInt32)
    case window(id: UInt32)

    static func resolve(displayID: UInt32?, windowID: UInt32) throws -> (target: CaptureTarget, viewport: Box) {
        if let displayID {
            let rect = CGDisplayBounds(displayID)
            guard rect.width > 0, rect.height > 0 else { throw Failure("Selected display is unavailable.") }
            return (.display(id: displayID), Box(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
        }
        return (.window(id: windowID), try Recording.windowBounds(windowID))
    }

    var label: String {
        switch self {
        case .display(let id): return "display:\(id)"
        case .window: return "window"
        }
    }

    /// Live viewport for pointing: displays stay fixed, windows are re-read (the scene window can change).
    func liveViewport(window: UInt32, initial: Box) throws -> Box {
        switch self {
        case .display: return initial
        case .window: return try Recording.windowBounds(window)
        }
    }

    /// Displays constrain scene windows; window captures follow them.
    func validateSceneWindow(_ number: UInt32, scene: Int, viewport: Box) throws {
        guard case .display = self else { return }
        let box = try Recording.windowBounds(number)
        guard Self.centerInside(box, viewport: viewport) else {
            throw Failure("Scene \(scene) window is outside the explicitly selected display.")
        }
    }

    nonisolated static func centerInside(_ box: Box, viewport: Box) -> Bool {
        let x = box.x + box.width / 2, y = box.y + box.height / 2
        return (viewport.x...(viewport.x + viewport.width)).contains(x) &&
            (viewport.y...(viewport.y + viewport.height)).contains(y)
    }
}

@MainActor final class Recording: NSObject, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate {
    private let state = RecordingState()
    private var stream: SCStream?
    private var monitor: Timer?
    private let onFailure: @MainActor () -> Void
    let target: CaptureTarget
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    let initialViewport: Box
    private(set) var epoch: Double = 0
    let source: URL

    static func start(window: DesktopWindow, target: CaptureTarget, source: URL, onFailure: @escaping @MainActor () -> Void) async throws -> Recording {
        guard CGPreflightScreenCaptureAccess() else { throw Failure("Showback needs Screen Recording permission. Enable it for the app that launches Showback in System Settings.") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        let rect: CGRect
        switch target {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw Failure("Selected display \(id) is unavailable.") }
            rect = display.frame
            filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == getpid() }, exceptingWindows: [])
        case .window:
            guard let selected = content.windows.first(where: { $0.windowID == window.number }) else { throw Failure("The selected window is no longer available for capture.") }
            rect = selected.frame
            filter = SCContentFilter(desktopIndependentWindow: selected)
        }
        let viewport = Box(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        let config = SCStreamConfiguration()
        let size = try captureDimensions(viewport: viewport, pixelScale: Double(filter.pointPixelScale))
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.scalesToFit = true
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.capturesAudio = false
        let recording = Recording(target: target, filter: filter, configuration: config, viewport: viewport, source: source, onFailure: onFailure)
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = source
        outputConfig.videoCodecType = .h264
        outputConfig.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: outputConfig, delegate: recording)
        let stream = SCStream(filter: filter, configuration: config, delegate: recording)
        recording.stream = stream
        try stream.addStreamOutput(recording, type: .screen, sampleHandlerQueue: DispatchQueue(label: "Showback.capture-clock"))
        try stream.addRecordingOutput(output)
        do {
            try await stream.startCapture()
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while !recording.state.ready {
                try recording.throwIfCaptureFailed()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure("Recording did not become ready within 10 seconds.") }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            recording.epoch = recording.state.startTime
            recording.monitor = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak recording] _ in
                MainActor.assumeIsolated {
                    guard let recording, recording.state.problem == nil else { return }
                    do {
                        switch recording.target {
                        case .display(let id):
                            guard CGDisplayIsOnline(id) != 0 else { throw CaptureFailure(message: "The captured display disconnected.") }
                        case .window: _ = try recording.viewport()
                        }
                    } catch {
                        recording.state.fail(error.localizedDescription)
                        recording.onFailure()
                    }
                }
            }
            return recording
        } catch {
            try? await stream.stopCapture()
            if let message = recording.state.problem { throw CaptureFailure(message: message) }
            throw error
        }
    }

    private init(target: CaptureTarget, filter: SCContentFilter, configuration: SCStreamConfiguration, viewport: Box, source: URL, onFailure: @escaping @MainActor () -> Void) {
        self.target = target; self.filter = filter; self.configuration = configuration
        self.initialViewport = viewport; self.source = source
        self.onFailure = onFailure
    }

    var failureReason: String? { state.problem }
    func throwIfCaptureFailed() throws { if let message = state.problem { throw CaptureFailure(message: message) } }

    /// - Throws: `CaptureFailure` when the window resized beyond stream tolerance.
    nonisolated static func checkResize(live: Box, initial: Box) throws {
        guard abs(live.width - initial.width) < 2, abs(live.height - initial.height) < 2 else {
            throw CaptureFailure(message: "The window was resized during the demo. Restart with its new size.")
        }
    }

    func viewport() throws -> Box {
        guard case .window(let id) = target else { return initialViewport }
        let box = try target.liveViewport(window: id, initial: initialViewport)
        try Self.checkResize(live: box, initial: initialViewport)
        return box
    }

    static func windowBounds(_ id: UInt32) throws -> Box {
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let info = windows.first, info[kCGWindowIsOnscreen as String] as? Bool == true,
              let raw = info[kCGWindowBounds as String] as? [String: Any],
              let x = raw["X"] as? Double, let y = raw["Y"] as? Double,
              let width = raw["Width"] as? Double, let height = raw["Height"] as? Double else { throw CaptureFailure(message: "The selected window is hidden or closed.") }
        return Box(x: x, y: y, width: width, height: height)
    }

    func screenshot(to url: URL, pointer: PointerTimeline, at time: Double) async throws {
        try throwIfCaptureFailed()
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let size = CGSize(width: image.width, height: image.height)
        var result = CIImage(cgImage: image)
        if let overlay = pointer.image(size: size, at: time) { result = CIImage(cgImage: overlay).composited(over: result) }
        guard let rendered = CIContext().createCGImage(result, from: result.extent),
              let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { throw Failure("Cannot encode scene screenshot.") }
        try data.write(to: url, options: .atomic)
    }

    func stop() async throws {
        monitor?.invalidate(); monitor = nil
        guard let stream else { return }
        self.stream = nil
        do { try await stream.stopCapture() } catch { state.fail(error.localizedDescription) }
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !state.finished {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure("Source video did not finalize. The partial file was preserved.") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try throwIfCaptureFailed()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen, sampleBuffer.isValid, sampleBuffer.imageBuffer != nil { state.sawFrame(sampleBuffer.presentationTimeStamp.seconds) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        state.fail(error.localizedDescription)
        Task { @MainActor [weak self] in self?.onFailure() }
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) { state.started() }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        state.finish(error: error.localizedDescription)
        Task { @MainActor [weak self] in self?.onFailure() }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { state.finish() }
}

func captureDimensions(viewport: Box, pixelScale: Double) throws -> CGSize {
    guard viewport.width > 0, viewport.height > 0, viewport.width.isFinite, viewport.height.isFinite,
          pixelScale > 0, pixelScale.isFinite else { throw Failure("Invalid capture dimensions.") }
    let scale = min(pixelScale, 1920 / max(viewport.width, viewport.height))
    return CGSize(width: max(2, Int(viewport.width * scale / 2) * 2), height: max(2, Int(viewport.height * scale / 2) * 2))
}

final class RecordingState: @unchecked Sendable {
    private let lock = NSLock()
    private var startedAt: Double?
    private var frameTime: Double?
    private var didFinish = false
    private var error: String?
    var ready: Bool { lock.lock(); defer { lock.unlock() }; return startedAt != nil && frameTime != nil }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return didFinish }
    var problem: String? { lock.lock(); defer { lock.unlock() }; return error }
    var startTime: Double { lock.lock(); defer { lock.unlock() }; return frameTime ?? startedAt ?? ProcessInfo.processInfo.systemUptime }
    func started() { lock.lock(); startedAt = ProcessInfo.processInfo.systemUptime; lock.unlock() }
    func sawFrame(_ time: Double) {
        lock.lock(); defer { lock.unlock() }
        if frameTime == nil { frameTime = time.isFinite && abs(time - ProcessInfo.processInfo.systemUptime) < 10 ? time : ProcessInfo.processInfo.systemUptime }
    }
    func finish(error message: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        didFinish = true
        if error == nil { error = message }
    }
    func fail(_ message: String) { lock.lock(); if error == nil { error = message }; lock.unlock() }
}
