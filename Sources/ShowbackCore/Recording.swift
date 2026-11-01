import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreImage

@MainActor final class Recording: NSObject, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate {
    private let state = RecordingState()
    private var stream: SCStream?
    private let windowID: UInt32
    private let displayID: UInt32?
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    let initialViewport: Box
    private(set) var epoch: Double = 0
    let source: URL

    static func start(window: DesktopWindow, displayID: UInt32?, source: URL) async throws -> Recording {
        guard CGPreflightScreenCaptureAccess() else { throw Failure("Showback needs Screen Recording permission. Enable it for the app that launches Showback in System Settings.") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let selected = content.windows.first(where: { $0.windowID == window.number }) else { throw Failure("The selected window is no longer available for capture.") }
        let filter: SCContentFilter
        let rect: CGRect
        if let displayID {
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw Failure("Selected display \(displayID) is unavailable.") }
            rect = display.frame
            filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == getpid() }, exceptingWindows: [])
        } else {
            rect = selected.frame
            filter = SCContentFilter(desktopIndependentWindow: selected)
        }
        let viewport = Box(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        let config = SCStreamConfiguration()
        let scale = min(2, 1920 / max(rect.width, rect.height))
        config.width = max(2, Int(rect.width * scale / 2) * 2)
        config.height = max(2, Int(rect.height * scale / 2) * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.capturesAudio = false
        let recording = Recording(windowID: window.number, displayID: displayID, filter: filter, configuration: config, viewport: viewport, source: source)
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
                try recording.check()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure("Recording did not become ready within 10 seconds.") }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            recording.epoch = recording.state.startTime
            return recording
        } catch {
            try? await stream.stopCapture()
            throw error
        }
    }

    private init(windowID: UInt32, displayID: UInt32?, filter: SCContentFilter, configuration: SCStreamConfiguration, viewport: Box, source: URL) {
        self.windowID = windowID; self.displayID = displayID; self.filter = filter; self.configuration = configuration
        self.initialViewport = viewport; self.source = source
    }

    func check() throws { if let message = state.problem { throw Failure(message) } }

    func viewport() throws -> Box {
        if displayID != nil { return initialViewport }
        let box = try Self.windowBounds(windowID)
        guard abs(box.width - initialViewport.width) < 2, abs(box.height - initialViewport.height) < 2 else {
            throw Failure("The window was resized during the demo. Restart with its new size.")
        }
        return box
    }

    static func windowBounds(_ id: UInt32) throws -> Box {
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let info = windows.first, let raw = info[kCGWindowBounds as String] as? [String: Any],
              let x = raw["X"] as? Double, let y = raw["Y"] as? Double,
              let width = raw["Width"] as? Double, let height = raw["Height"] as? Double else { throw Failure("The selected window disappeared.") }
        return Box(x: x, y: y, width: width, height: height)
    }

    func screenshot(to url: URL, pointer: PointerTimeline, at time: Double) async throws {
        try check()
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let size = CGSize(width: image.width, height: image.height)
        var result = CIImage(cgImage: image)
        if let overlay = pointer.image(size: size, at: time) { result = CIImage(cgImage: overlay).composited(over: result) }
        guard let rendered = CIContext().createCGImage(result, from: result.extent),
              let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { throw Failure("Cannot encode scene screenshot.") }
        try data.write(to: url, options: .atomic)
    }

    func stop() async throws {
        guard let stream else { return }
        self.stream = nil
        try await stream.stopCapture()
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !state.finished {
            try check()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure("Source video did not finalize. The partial file was preserved.") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try check()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen, sampleBuffer.isValid, sampleBuffer.imageBuffer != nil { state.sawFrame(sampleBuffer.presentationTimeStamp.seconds) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) { state.fail(error.localizedDescription) }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) { state.started() }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) { state.fail(error.localizedDescription) }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { state.finish() }
}

private final class RecordingState: @unchecked Sendable {
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
    func finish() { lock.lock(); didFinish = true; lock.unlock() }
    func fail(_ message: String) { lock.lock(); error = message; didFinish = true; lock.unlock() }
}
