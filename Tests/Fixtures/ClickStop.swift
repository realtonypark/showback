import ApplicationServices
import Foundation

// The desktop inventory omits status-bar-level panels; use public AX for this control check.
let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, key as CFString, &value)
    return value
}
func findStop(_ element: AXUIElement) -> AXUIElement? {
    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
       attribute(element, kAXTitleAttribute) as? String == "Stop" {
        return element
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = findStop(child) { return found }
    }
    return nil
}
let deadline = ProcessInfo.processInfo.systemUptime + 5
repeat {
    let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    for window in windows where attribute(window, kAXTitleAttribute) as? String == "Showback Demo" {
        if let button = findStop(window) {
            // Retry observation only; a press can be delivered even when AX reports an error.
            guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                fatalError("Showback Stop press failed; not retrying a possibly delivered action")
            }
            print("Stop pressed through Accessibility")
            exit(0)
        }
    }
    Thread.sleep(forTimeInterval: 0.05)
} while ProcessInfo.processInfo.systemUptime < deadline
fatalError("Showback Stop control was not accessible within 5 seconds")
