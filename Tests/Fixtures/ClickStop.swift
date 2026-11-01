import ApplicationServices
import Foundation

// The desktop inventory omits status-bar-level panels; use public AX for this control check.
let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, key as CFString, &value)
    return value
}
func clickStop(_ element: AXUIElement) -> Bool {
    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
       attribute(element, kAXTitleAttribute) as? String == "Stop" {
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
    return (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains(where: clickStop)
}
let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
guard windows.contains(where: { attribute($0, kAXTitleAttribute) as? String == "Showback Demo" && clickStop($0) }) else {
    fatalError("Showback Stop control was not accessible")
}
print("Stop pressed through Accessibility")
