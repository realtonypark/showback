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
        func time() -> Double { max(0, ProcessInfo.processInfo.systemUptime - epoch) }
        do {
            try assets.verifyInstallation()
            try await desktop.start(recording: !options.liveOnly)
            let voice = try SettingsStore().voice(in: assets.catalog)
            step = "Narration preparation"
            let clips = try await Speech(assets: assets).prepare(script.scenes, voice: voice, in: bundle.root.appendingPathComponent("narration")) { print($0); fflush(stdout) }
            try Task.checkCancellation()
            step = "Capture setup"
            try await desktop.focus()
            let window = try desktop.selected()
            let initialViewport: Box
            if let displayID = script.displayID {
                let rect = CGDisplayBounds(displayID)
                guard rect.width > 0, rect.height > 0 else { throw Failure("Selected display is unavailable.") }
                initialViewport = Box(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
            } else { initialViewport = try Recording.windowBounds(window.number) }
            presentation = Presentation(viewport: initialViewport, epoch: epoch)
            stop = StopControl(viewport: initialViewport, onStop: onStop)
            if !options.liveOnly {
                recording = try await Recording.start(window: window, displayID: script.displayID, source: bundle.root.appendingPathComponent("recording.mp4"), onFailure: onStop)
                epoch = recording!.epoch
            } else { epoch = ProcessInfo.processInfo.systemUptime }
            let viewport: Box
            if let recording { viewport = try recording.viewport() }
            else { viewport = initialViewport }
            presentation?.begin(at: epoch)
            try bundle.start(target: ["app": script.app, "window": window.title, "windowID": window.number,
                                      "capture": script.displayID.map { "display:\($0)" } ?? "window"], epoch: epoch)
            print("Presenting \(script.title)"); fflush(stdout)
            for (index, scene) in script.scenes.enumerated() {
                step = "Scene \(index + 1), window selection"
                print("Scene \(index + 1)/\(script.scenes.count)"); fflush(stdout)
                try Task.checkCancellation()
                try recording?.check()
                let sceneApp = scene.app ?? script.app
                let sceneTitle = scene.windowTitle ?? (sceneApp == script.app ? script.windowTitle : nil)
                if desktop.app != sceneApp || desktop.title != sceneTitle {
                    try await desktop.select(app: sceneApp, title: sceneTitle)
                    try await desktop.focus()
                }
                let currentWindow = try desktop.selected()
                if script.displayID != nil {
                    let box = try Recording.windowBounds(currentWindow.number)
                    let x = box.x + box.width / 2, y = box.y + box.height / 2
                    guard (viewport.x...(viewport.x + viewport.width)).contains(x), (viewport.y...(viewport.y + viewport.height)).contains(y) else {
                        throw Failure("Scene \(index + 1) window is outside the explicitly selected display.")
                    }
                }
                try bundle.record("scene", at: time(), scene: index + 1, data: ["say": scene.say ?? "", "app": sceneApp, "windowID": currentWindow.number])
                step = "Scene \(index + 1), narration"
                let playback = try clips[index].map { try AudioPlayback(clip: $0, epoch: epoch, mute: options.mute) }
                if let playback {
                    segments.append(playback.segment)
                    try bundle.record("narration-start", at: playback.segment.start, scene: index + 1,
                                      data: ["clock": playback.usesDeviceClock ? "audio-device" : "monotonic", "muted": options.mute])
                }
                let narration = Task { @MainActor in try await playback?.wait() }
                do {
                    try await withTaskCancellationHandler(operation: {
                        for (actionIndex, action) in scene.actions.enumerated() {
                            step = "Scene \(index + 1), action \(actionIndex + 1)"
                            try Task.checkCancellation()
                            try recording?.check()
                            let result = try await desktop.execute(action) { target in
                                let current = try recording?.viewport() ?? (script.displayID == nil ? Recording.windowBounds(currentWindow.number) : viewport)
                                try await presentation?.point(target: target, viewport: current)
                                try bundle.record("point", at: time(), scene: index + 1, data: ["x": target.x, "y": target.y, "width": target.width, "height": target.height])
                            }
                            try bundle.record("action", at: time(), scene: index + 1, data: result)
                        }
                        if let expected = scene.expect {
                            step = "Scene \(index + 1), expect"
                            let observed = try await desktop.waitFor(expected)
                            try bundle.record("checked", at: time(), scene: index + 1, data: observed)
                        }
                        if let absent = scene.absent {
                            step = "Scene \(index + 1), absent"
                            let observed = try await desktop.waitForAbsent(absent)
                            try bundle.record("absent-checked", at: time(), scene: index + 1, data: observed)
                        }
                        step = "Scene \(index + 1), narration"
                        try await narration.value
                    }, onCancel: { narration.cancel() })
                } catch {
                    narration.cancel(); playback?.stop()
                    _ = try? await narration.value
                    if let last = segments.last, playback != nil {
                        segments.removeLast()
                        let duration = min(last.duration, max(0, time() - last.start))
                        if duration > 0.01 { segments.append(NarrationSegment(url: last.url, start: last.start, duration: duration)) }
                    }
                    throw error
                }
                if let recording, !scene.actions.isEmpty || scene.expect != nil || scene.absent != nil {
                    step = "Scene \(index + 1), screenshot"
                    try await recording.screenshot(to: bundle.root.appendingPathComponent(String(format: "frames/scene-%02d.png", index + 1)),
                                                   pointer: presentation!.timeline, at: time())
                }
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
        do { try bundle.media(pointer: pointer, narration: segments) }
        catch {
            status = status == .cancelled ? .cancelled : .failed
            problem = [problem, error.localizedDescription].compactMap { $0 }.joined(separator: "\n")
        }
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
        if let cleanupError {
            status = status == .cancelled ? .cancelled : .failed
            if problem != cleanupError { problem = [problem, cleanupError].compactMap { $0 }.joined(separator: "\n") }
        }
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
}
