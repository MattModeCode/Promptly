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

    /// Selected text in the captured app, for the inverse-capture sheet (Stage 5). Tries the
    /// non-destructive AX read first (`kAXSelectedTextAttribute` of the focused element);
    /// falls back to a synthesized ⌘C that snapshots and restores the clipboard so the HARD
    /// RULE (never leave the clipboard mutated) holds. Must run BEFORE we activate our own
    /// app, while the host is still frontmost. Returns nil if nothing is selected.
    static func captureSelection(pid: pid_t) -> String? {
        if let s = selectedTextViaAX(pid: pid), !s.isEmpty { return s }
        return selectionViaCopy()
    }

    private static func selectedTextViaAX(pid: pid_t) -> String? {
        let appEl = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let el = focused as! AXUIElement
        var selRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &selRef) == .success
        else { return nil }
        return selRef as? String
    }

    private static func selectionViaCopy() -> String? {
        let pb = NSPasteboard.general
        // Snapshot every item/type so restore is byte-exact (mirrors PasteCore Strategy A).
        let saved: [[String: Data]] = pb.pasteboardItems?.map { item in
            var dict: [String: Data] = [:]
            for type in item.types { if let d = item.data(forType: type) { dict[type.rawValue] = d } }
            return dict
        } ?? []

        let before = pb.changeCount
        let cKey: CGKeyCode = 8 // 'c'
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false) else { return nil }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)

        // Wait (bounded) for the host app to write the copy, then read + restore.
        let ceiling: useconds_t = 200_000, step: useconds_t = 10_000
        var waited: useconds_t = 0
        while waited < ceiling {
            if pb.changeCount != before { break }
            usleep(step); waited += step
        }
        let copied = pb.string(forType: .string)
        restoreClipboard(saved)   // free function in PasteCore — same restore the paste path uses
        return (copied?.isEmpty == false) ? copied : nil
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
