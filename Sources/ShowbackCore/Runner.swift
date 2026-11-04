import AppKit

@MainActor final class Runner {
    let assets: Assets
    init(assets: Assets) { self.assets = assets }

    func run(_ options: RunOptions, onStop: @escaping () -> Void) async throws -> RunStatus {
        let lockURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Showback/run.lock")
        let lock = try RunLock(url: lockURL)
        defer { lock.release() }
        let script = try DemoScript.load(options.script)
        let bundle = try RunBundle(root: options.output, script: options.script, title: script.title, recording: !options.liveOnly)
        let desktop = try Desktop(binary: assets.url(for: "desktop-runtime"), app: script.app, title: script.windowTitle,
                                  sessionFile: lockURL.deletingLastPathComponent().appendingPathComponent("desktop-session.json"))
        var recording: Recording?
        var presentation: Presentation?
        var stop: StopControl?
        var segments: [NarrationSegment] = []
        var status = RunStatus.completed
        var problem: String?
        var step = "Preflight"
        var epoch = ProcessInfo.processInfo.systemUptime
        do {
            try assets.verifyInstallation()
            try await desktop.start(recording: !options.liveOnly)
            let voice = try SettingsStore().voice(in: Assets.loadCatalog())
            step = "Narration preparation"
            let clips = try await Speech(assets: assets).prepare(script.scenes, voice: voice, in: bundle.root.appendingPathComponent("narration")) { print($0); fflush(stdout) }
            try Task.checkCancellation()
            step = "Capture setup"
            try await desktop.focus()
            let window = try desktop.currentWindow
            let (target, initialViewport) = try CaptureTarget.resolve(displayID: script.displayID, windowID: window.number)
            presentation = Presentation(viewport: initialViewport, epoch: epoch)
            stop = StopControl(viewport: initialViewport, onStop: onStop)
            if !options.liveOnly {
                let started = try await Recording.start(window: window, target: target, source: bundle.root.appendingPathComponent("recording.mp4"), onFailure: onStop)
                recording = started
                epoch = started.epoch
            } else { epoch = ProcessInfo.processInfo.systemUptime }
            let viewport: Box
            if let recording { viewport = try recording.viewport() } else { viewport = initialViewport }
            presentation?.begin(at: epoch)
            try bundle.start(target: ["app": script.app, "window": window.title, "windowID": window.number,
                                      "capture": target.label], epoch: epoch)
            print("Presenting \(script.title)"); fflush(stdout)
            let context = SceneContext(script: script, clips: clips, desktop: desktop, recording: recording,
                                       presentation: presentation, bundle: bundle, viewport: viewport,
                                       options: options, epoch: epoch, target: target)
            for (index, scene) in script.scenes.enumerated() {
                try await runScene(index: index, scene: scene, context: context, step: &step, segments: &segments)
            }
        } catch {
            if let message = recording?.failureReason ?? (error as? CaptureFailure)?.message {
                status = .failed; problem = "\(step): \(message)"
            } else {
                status = Task.isCancelled || error is CancellationError ? .cancelled : .failed
                problem = status == .cancelled ? "Cancelled." : "\(step): \(error.localizedDescription)"
            }
        }
        let pointer = presentation?.timeline ?? PointerTimeline()
        presentation?.close(); stop?.close()
        do { try bundle.attachMedia(pointer: pointer, narration: segments) } catch {
            status = status == .cancelled ? .cancelled : .failed
            problem = [problem, error.localizedDescription].compactMap { $0 }.joined(separator: "\n")
        }
        let outcome = await finalize(recording: recording, desktop: desktop, bundle: bundle, segments: segments,
                                     pointer: pointer, status: status, problem: problem)
        let mediaReady = outcome.mediaReady
        status = outcome.status
        problem = outcome.problem
        if Task.isCancelled, status == .completed { status = .cancelled; problem = "Cancelled." }
        try bundle.finish(status, error: problem, mediaReady: mediaReady)
        print("\(status.rawValue): \(bundle.root.path)"); fflush(stdout)
        if let video = bundle.video {
            print("\(status == .completed ? "Video" : "Partial video"): \(video.path)")
        }
        print("Summary: \(bundle.root.appendingPathComponent("summary.md").path)"); fflush(stdout)
        if let problem { FileHandle.standardError.write(Data((problem + "\n").utf8)) }
        return status
    }

    nonisolated static func resolveSceneTarget(scene: Scene, scriptApp: String, scriptWindow: String?) -> (app: String, title: String?) {
        let app = scene.app ?? scriptApp
        return (app, scene.windowTitle ?? (app == scriptApp ? scriptWindow : nil))
    }

    nonisolated static func trimmedSegment(_ last: NarrationSegment, at time: Double) -> NarrationSegment? {
        let duration = min(last.duration, max(0, time - last.start))
        return duration > 0.01 ? NarrationSegment(url: last.url, start: last.start, duration: duration) : nil
    }

    // Internal so RunnerTests can drive scene orchestration without a display or installed assets.
    struct SceneContext {
        let script: DemoScript
        let clips: [SpeechClip?]
        let desktop: Desktop
        let recording: Recording?
        let presentation: Presentation?
        let bundle: RunBundle
        let viewport: Box
        let options: RunOptions
        let epoch: Double
        let target: CaptureTarget

        func time() -> Double { max(0, ProcessInfo.processInfo.systemUptime - epoch) }
    }

    func runScene(index: Int, scene: Scene, context: SceneContext, step: inout String, segments: inout [NarrationSegment]) async throws {
        let (currentWindow, playback) = try await prepareScene(index: index, scene: scene, context: context, step: &step, segments: &segments)
        try await runActions(index: index, scene: scene, context: context, currentWindow: currentWindow, playback: playback, step: &step, segments: &segments)
        if let recording = context.recording, let presentation = context.presentation,
           !scene.actions.isEmpty || scene.expect != nil || scene.absent != nil {
            step = "Scene \(index + 1), screenshot"
            try await recording.screenshot(to: context.bundle.root.appendingPathComponent(String(format: "frames/scene-%02d.png", index + 1)),
                                           pointer: presentation.timeline, at: context.time())
        }
    }

    func prepareScene(index: Int, scene: Scene, context: SceneContext, step: inout String, segments: inout [NarrationSegment]) async throws -> (DesktopWindow, AudioPlayback?) {
        let script = context.script
        let desktop = context.desktop
        let recording = context.recording
        let bundle = context.bundle
        step = "Scene \(index + 1), window selection"
        print("Scene \(index + 1)/\(script.scenes.count)"); fflush(stdout)
        try Task.checkCancellation()
        try recording?.throwIfCaptureFailed()
        let (sceneApp, sceneTitle) = Self.resolveSceneTarget(scene: scene, scriptApp: script.app, scriptWindow: script.windowTitle)
        if desktop.app != sceneApp || desktop.title != sceneTitle {
            try await desktop.resolveWindow(app: sceneApp, title: sceneTitle)
            try await desktop.focus()
        }
        let currentWindow = try desktop.currentWindow
        try context.target.validateSceneWindow(currentWindow.number, scene: index + 1, viewport: context.viewport)
        try bundle.record(.scene, at: context.time(), scene: index + 1, data: ["say": scene.say ?? "", "app": sceneApp, "windowID": currentWindow.number])
        step = "Scene \(index + 1), narration"
        let playback = try context.clips[index].map { try AudioPlayback(clip: $0, epoch: context.epoch, mute: context.options.mute) }
        if let playback {
            segments.append(playback.segment)
            try bundle.record(.narrationStart, at: playback.segment.start, scene: index + 1,
                              data: ["clock": playback.usesDeviceClock ? "audio-device" : "monotonic", "muted": context.options.mute])
        }
        return (currentWindow, playback)
    }

    func runActions(index: Int, scene: Scene, context: SceneContext, currentWindow: DesktopWindow, playback: AudioPlayback?, step: inout String, segments: inout [NarrationSegment]) async throws {
        let desktop = context.desktop
        let recording = context.recording
        let presentation = context.presentation
        let bundle = context.bundle
        let narration = Task { @MainActor in try await playback?.wait() }
        do {
            try await withTaskCancellationHandler(operation: {
                for (actionIndex, action) in scene.actions.enumerated() {
                    step = "Scene \(index + 1), action \(actionIndex + 1)"
                    try Task.checkCancellation()
                    try recording?.throwIfCaptureFailed()
                    let result = try await desktop.execute(action) { target in
                        let current = try recording?.viewport() ?? context.target.liveViewport(window: currentWindow.number, initial: context.viewport)
                        try await presentation?.point(target: target, viewport: current)
                        try bundle.record(.point, at: context.time(), scene: index + 1, data: ["x": target.x, "y": target.y, "width": target.width, "height": target.height])
                    }
                    try bundle.record(.action, at: context.time(), scene: index + 1, data: result)
                }
                if let expected = scene.expect {
                    step = "Scene \(index + 1), expect"
                    let observed = try await desktop.waitFor(expected)
                    try bundle.record(.checked, at: context.time(), scene: index + 1, data: observed)
                }
                if let absent = scene.absent {
                    step = "Scene \(index + 1), absent"
                    let observed = try await desktop.waitForAbsent(absent)
                    try bundle.record(.absentChecked, at: context.time(), scene: index + 1, data: observed)
                }
                step = "Scene \(index + 1), narration"
                try await narration.value
            }, onCancel: { narration.cancel() })
        } catch {
            narration.cancel(); playback?.stop()
            _ = try? await narration.value
            if let last = segments.last, playback != nil {
                segments.removeLast()
                if let trimmed = Self.trimmedSegment(last, at: context.time()) { segments.append(trimmed) }
            }
            throw error
        }
    }

    private func finalize(recording: Recording?, desktop: Desktop, bundle: RunBundle, segments: [NarrationSegment],
                          pointer: PointerTimeline, status: RunStatus, problem: String?) async -> (mediaReady: Bool, status: RunStatus, problem: String?) {
        // Cleanup must finish even when the presentation task was cancelled.
        let cleanup = Task { @MainActor () -> (Bool, String?) in
            var mediaReady = false
            var error: String?
            do {
                if let recording {
                    try await recording.stop()
                    print("Exporting recording"); fflush(stdout)
                    try await MediaExport.render(source: recording.source, output: bundle.root.appendingPathComponent("demo.mp4"), narration: segments, pointer: pointer)
                    mediaReady = true
                }
            } catch let failure { error = failure.localizedDescription }
            do { try await desktop.end() } catch let failure { error = [error, failure.localizedDescription].compactMap { $0 }.joined(separator: "\n") }
            return (mediaReady, error)
        }
        let (mediaReady, cleanupError) = await cleanup.value
        var status = status
        var problem = problem
        if let cleanupError {
            status = status == .cancelled ? .cancelled : .failed
            if problem != cleanupError { problem = [problem, cleanupError].compactMap { $0 }.joined(separator: "\n") }
        }
        return (mediaReady, status, problem)
    }
}
