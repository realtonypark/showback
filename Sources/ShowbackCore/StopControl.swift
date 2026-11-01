import AppKit

@MainActor final class StopControl: NSObject {
    private let panel: NSPanel
    private let onStop: () -> Void
    private let button: NSButton
    init(viewport: Box, onStop: @escaping () -> Void) {
        self.onStop = onStop
        let frame = Presentation.appKitFrame(viewport)
        panel = NSPanel(contentRect: NSRect(x: frame.maxX - 110, y: frame.minY + 10, width: 100, height: 38),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        button = NSButton(title: "Stop", target: nil, action: nil)
        super.init()
        panel.title = "Showback Demo"
        panel.isReleasedWhenClosed = false; panel.level = .statusBar
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 8, y: 3, width: 84, height: 32)
        button.target = self; button.action = #selector(stop)
        panel.contentView?.addSubview(button)
        panel.orderFrontRegardless()
    }
    @objc private func stop() { button.isEnabled = false; onStop() }
    func close() { panel.close() }
}
