import AppKit
import WebKit

let arguments = CommandLine.arguments
guard let index = arguments.firstIndex(of: "--display"), index + 1 < arguments.count,
      let id = UInt32(arguments[index + 1]), id != CGMainDisplayID(),
      let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }),
      let pageIndex = arguments.firstIndex(of: "--page"), pageIndex + 1 < arguments.count else {
    fatalError("Supply --display VIRTUAL_DISPLAY_ID --page /absolute/browser.html")
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let frame = NSRect(x: screen.frame.minX + 120, y: screen.frame.minY + 80, width: 900, height: 620)
let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false, screen: screen)
window.title = "Showback Browser Fixture"
window.isReleasedWhenClosed = false
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = .nonPersistent()
let browser = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
browser.autoresizingMask = [.width, .height]
window.contentView!.addSubview(browser)
let page = URL(fileURLWithPath: arguments[pageIndex + 1])
browser.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
window.makeKeyAndOrderFront(nil)
window.setFrame(frame, display: true)
app.activate(ignoringOtherApps: true)
app.run()
