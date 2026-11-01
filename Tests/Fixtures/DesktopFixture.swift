import AppKit

final class FixtureController: NSObject {
    let status = NSTextField(labelWithString: "Signed out")
    let count = NSTextField(labelWithString: "Count: 0")
    var value = 0
    let field = NSTextField(string: "")
    @objc func signIn() {
        status.stringValue = "Welcome, demo user"
        if let i = CommandLine.arguments.firstIndex(of: "--events"), i + 1 < CommandLine.arguments.count {
            let value = "\(ProcessInfo.processInfo.systemUptime)\n"
            try! value.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
        }
    }
    @objc func moveWindow() {
        guard let window = status.window, let screen = window.screen else { return }
        window.setFrameOrigin(NSPoint(x: screen.frame.minX + 360, y: screen.frame.minY + 180))
        status.stringValue = "Window moved"
    }
    @objc func increment() { value += 1; count.stringValue = "Count: \(value)" }
    @objc func reset() { status.stringValue = "Signed out"; value = 0; count.stringValue = "Count: 0"; field.stringValue = "" }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = FixtureController()
let args = CommandLine.arguments
let wanted = args.firstIndex(of: "--display").flatMap { i in i + 1 < args.count ? UInt32(args[i + 1]) : nil }
guard let wanted, wanted != CGMainDisplayID(),
      let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == wanted }) else {
    fatalError("Supply --display VIRTUAL_DISPLAY_ID")
}
let frame = NSRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 760, height: 540)
let window = NSWindow(contentRect: frame,
                      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false, screen: screen)
window.title = "Showback Fixture"
window.isReleasedWhenClosed = false
let content = window.contentView!
let heading = NSTextField(labelWithString: "Account")
heading.font = .systemFont(ofSize: 30, weight: .semibold)
heading.frame = NSRect(x: 48, y: 420, width: 600, height: 45)
content.addSubview(heading)
controller.status.frame = NSRect(x: 48, y: 360, width: 600, height: 30)
controller.status.setAccessibilityIdentifier("status")
controller.status.font = .systemFont(ofSize: 20)
content.addSubview(controller.status)
let button = NSButton(title: "Sign in", target: controller, action: #selector(FixtureController.signIn))
button.bezelStyle = .rounded
button.frame = NSRect(x: 48, y: 292, width: 140, height: 40)
button.setAccessibilityIdentifier("sign-in")
content.addSubview(button)
let field = controller.field
field.placeholderString = "Demo note"
field.setAccessibilityLabel("Demo note")
field.frame = NSRect(x: 48, y: 212, width: 400, height: 35)
content.addSubview(field)
controller.count.frame = NSRect(x: 48, y: 142, width: 300, height: 30)
content.addSubview(controller.count)
let increment = NSButton(title: "Increment", target: controller, action: #selector(FixtureController.increment))
increment.bezelStyle = .rounded
increment.frame = NSRect(x: 48, y: 72, width: 140, height: 40)
content.addSubview(increment)
let reset = NSButton(title: "Reset", target: controller, action: #selector(FixtureController.reset))
reset.bezelStyle = .rounded
reset.frame = NSRect(x: 600, y: 72, width: 100, height: 40)
content.addSubview(reset)
let move = NSButton(title: "Move window", target: controller, action: #selector(FixtureController.moveWindow))
move.bezelStyle = .rounded
move.frame = NSRect(x: 450, y: 72, width: 140, height: 40)
content.addSubview(move)
window.makeKeyAndOrderFront(nil)
window.setFrame(frame, display: true)
app.activate(ignoringOtherApps: true)
app.run()
