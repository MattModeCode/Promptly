import AppKit
import ApplicationServices

struct CapturedApp {
    let pid: pid_t
    let app: NSRunningApplication
    let screen: NSScreen
}

enum Capture {
    static func captureFrontmostApp() -> CapturedApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let screen = screenForApp(pid: pid) ?? NSScreen.main ?? NSScreen.screens[0]
        return CapturedApp(pid: pid, app: app, screen: screen)
    }

    private static func screenForApp(pid: pid_t) -> NSScreen? {
        let axApp = AXUIElementCreateApplication(pid)
        var windowVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowVal) == .success,
              let window = windowVal else { return nil }
        var posVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &posVal) == .success,
              let posVal = posVal else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        let nsPoint = NSPoint(x: point.x, y: point.y)
        return NSScreen.screens.first { NSMouseInRect(nsPoint, $0.frame, false) }
    }
}
