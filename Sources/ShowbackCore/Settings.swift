import AppKit

@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let assets: Assets
    private let catalog: AssetCatalog
    private let voices = NSPopUpButton()
    private let preview = NSButton(title: "Preview", target: nil, action: nil)
    private var previewTask: Task<Void, Never>?
    private var playback: AudioPlayback?

    init(assets: Assets) throws {
        self.assets = assets
        catalog = try assets.catalog
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 210), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Showback Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = window.contentView!
        for (label, y) in [("Voice", 142.0), ("Model", 96.0)] {
            let field = NSTextField(labelWithString: label)
            field.frame = NSRect(x: 32, y: y, width: 90, height: 24)
            content.addSubview(field)
        }
        voices.frame = NSRect(x: 132, y: 137, width: 306, height: 32)
        voices.addItems(withTitles: catalog.voices.map(\.name))
        let selected = try SettingsStore().voice(in: catalog)
        voices.selectItem(at: catalog.voices.firstIndex(where: { $0.id == selected }) ?? 0)
        voices.target = self; voices.action = #selector(changeVoice)
        voices.setAccessibilityLabel("Voice")
        content.addSubview(voices)
        let model = NSTextField(labelWithString: catalog.model)
        model.frame = NSRect(x: 132, y: 96, width: 280, height: 24)
        content.addSubview(model)
        preview.frame = NSRect(x: 132, y: 34, width: 100, height: 32)
        preview.bezelStyle = .rounded; preview.target = self; preview.action = #selector(previewVoice)
        content.addSubview(preview)
        do {
            try assets.verifyInstallation()
            let status = NSImageView(frame: NSRect(x: 416, y: 98, width: 18, height: 18))
            status.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Model installed")
            status.contentTintColor = .systemGreen
            content.addSubview(status)
        } catch {
            preview.isEnabled = false
            let status = NSTextField(wrappingLabelWithString: error.localizedDescription)
            status.frame = NSRect(x: 132, y: 30, width: 306, height: 56)
            content.addSubview(status)
        }
    }

    func show() { window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowWillClose(_ notification: Notification) { previewTask?.cancel(); playback?.stop() }

    @objc private func changeVoice() {
        previewTask?.cancel(); playback?.stop()
        do { try SettingsStore().save(voice: catalog.voices[voices.indexOfSelectedItem].id, in: catalog) }
        catch { showError(error) }
    }

    @objc private func previewVoice() {
        if previewTask != nil { previewTask?.cancel(); playback?.stop(); return }
        preview.title = "Stop"
        let voice = catalog.voices[voices.indexOfSelectedItem].id
        previewTask = Task { @MainActor in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("showback-preview-\(UUID().uuidString)")
            defer { preview.title = "Preview"; previewTask = nil; playback = nil; try? FileManager.default.removeItem(at: folder) }
            do {
                let clips = try await Speech(assets: assets).prepare([Scene(say: "Showback is ready. Let's walk through the change.", actions: [], expect: nil)], voice: voice, in: folder) { _ in }
                try Task.checkCancellation()
                guard let clip = clips[0] else { throw Failure("No voice preview was generated.") }
                playback = try AudioPlayback(clip: clip, epoch: ProcessInfo.processInfo.systemUptime, mute: false)
                try await playback?.wait()
            } catch { if !Task.isCancelled { showError(error) } }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Showback"
        alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: window)
    }
}
