// PasteCore.swift — extracted VERBATIM from PasteProbe.swift (the spike).
//
// One source of truth: PasteService and the Tier A tests both compile against this file
// so they cannot drift from the proven spike behavior (DESIGN §5, CLAUDE.md "extract it
// verbatim"). Do NOT alter these functions — fix the cause in the spike, then re-extract.

import AppKit
import ApplicationServices

// MARK: - Logging helpers

func logAX(_ s: String)   { print("[AX] \(s)") }
func logCB(_ s: String)   { print("[CB] \(s)") }
func logMain(_ s: String) { print(">>> \(s)") }

// MARK: - Accessibility permission

func ensureAccessibilityTrust() -> Bool {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(opts)
    if trusted {
        logMain("Accessibility permission: granted.")
    } else {
        logMain("Accessibility permission: NOT granted.")
        logMain("Grant it under System Settings → Privacy & Security → Accessibility,")
        logMain("then re-run. (When run via `swift`, you grant the Terminal app itself —")
        logMain("the grant does NOT transfer to the bundled app later. DESIGN §4.)")
    }
    return trusted
}

// MARK: - Frontmost app capture (must happen BEFORE we'd show any panel — invariant 1)

func captureFrontmostApp() -> NSRunningApplication? {
    let app = NSWorkspace.shared.frontmostApplication
    if let app = app {
        logMain("Frontmost app captured: \(app.localizedName ?? "?") (pid \(app.processIdentifier))")
    } else {
        logMain("Could not determine frontmost app.")
    }
    return app
}

// MARK: - AX read helpers

/// Copy an attribute as a Swift String, or nil if absent/unreadable/not-a-string.
func axString(_ el: AXUIElement, _ attr: String) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
    return ref as? String
}

/// Is an attribute settable on this element? (AXUIElementIsAttributeSettable)
func axSettable(_ el: AXUIElement, _ attr: String) -> Bool {
    var settable: DarwinBoolean = false
    let err = AXUIElementIsAttributeSettable(el, attr as CFString, &settable)
    return err == .success && settable.boolValue
}

/// Does the element expose an attribute at all (regardless of value type)?
func axHasAttribute(_ el: AXUIElement, _ attr: String) -> Bool {
    var ref: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success
}

/// The system-wide focused UI element, or nil if unreadable (typical of Electron).
/// NOTE (review D1/D2): with our nonactivating panel up and KEY, this resolves to the
/// PANEL's own text field, not the host app — which is exactly why the real PasteService
/// must NOT use this. Kept here only to LOG the divergence as Gate 0 evidence.
func copyFocusedElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
    guard err == .success, let untyped = focusedRef else {
        logAX("Could not read system-wide focused element: AXError \(err.rawValue).")
        return nil
    }
    return (untyped as! AXUIElement)
}

/// The focused UI element *within a specific app*, by pid. THIS is the mechanism the real
/// PasteService extracts: it targets the captured host app regardless of what is frontmost
/// or key now, so invariant 2 (paste into the captured app, not the current frontmost / our
/// own panel) is enforced in code, not prose. (DESIGN §1 invariant 2; review D1.)
func copyFocusedElement(forPid pid: pid_t) -> AXUIElement? {
    let appEl = AXUIElementCreateApplication(pid)
    var focusedRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(
        appEl, kAXFocusedUIElementAttribute as CFString, &focusedRef)
    guard err == .success, let untyped = focusedRef else {
        logAX("Could not read focused element for pid \(pid): AXError \(err.rawValue).")
        return nil
    }
    return (untyped as! AXUIElement)
}

/// Current character count of an element's value, or nil if unreadable. The read-back
/// anchor (below) needs the BEFORE length to prove the marker is one WE inserted.
func axValueLength(_ el: AXUIElement) -> Int? {
    axString(el, kAXValueAttribute as String).map { $0.count }
}

// MARK: - Read-back verification (DESIGN §2.1 — the whole point)

/// After a write, re-read the field and assert the marker is one WE put there — anchored
/// on the LENGTH DELTA, not a naive substring match (review A3). A bare `contains(marker)`
/// false-positives when the field already held the marker text; the real app pastes
/// arbitrary prompt text into possibly-non-empty fields, so presence alone proves nothing.
/// The anchor: after inserting `text`, the field's character count must have grown by
/// exactly `text.count` (selected-text insert at a collapsed caret) OR equal `text.count`
/// when value-set into an empty field. Presence AND delta together prove authorship.
/// Caveat: a non-collapsed selection at insert time replaces the selection, so the delta
/// won't equal text.count — the spike clicks into a collapsed caret, so this holds here;
/// the real app must read the selected range to handle replace-selection precisely.
struct ReadBack { let confirmed: Bool; let value: String?; let beforeLen: Int?; let afterLen: Int? }

func readBackConfirms(_ el: AXUIElement, inserted text: String, beforeLen: Int?) -> ReadBack {
    let value = axString(el, kAXValueAttribute as String) ?? axString(el, kAXSelectedTextAttribute as String)
    guard let v = value else { return ReadBack(confirmed: false, value: nil, beforeLen: beforeLen, afterLen: nil) }
    let afterLen = v.count
    let present = v.contains(text)
    let grewByInsert = beforeLen.map { afterLen == $0 + text.count } ?? false
    let valueSetExact = (beforeLen ?? 0) == 0 && afterLen == text.count
    return ReadBack(confirmed: present && (grewByInsert || valueSetExact),
                    value: v, beforeLen: beforeLen, afterLen: afterLen)
}

// MARK: - Capability probe (DESIGN §2.2 — choose the path from evidence, NOT a fall-through)

enum PastePath: String {
    case bSelectedText = "B — selected-text (insert at caret)"
    case bValueSet     = "B — value-set (empty field, safe)"
    case aClipboard    = "A — clipboard + ⌘V"
}

struct Evidence {
    var focusedReadable = false
    var role: String? = nil
    var selectedTextSettable = false
    var valueSettable = false
    var hasSelectedTextRange = false
    var fieldWasEmpty: Bool? = nil   // nil = couldn't tell
    var chosenPath: PastePath? = nil
    var strategyFired: String = "(none)"
    var readBackConfirmed: Bool = false
    var readBackValue: String? = nil
    var clipboardClean: Bool? = nil
    // Review D2: the key-panel divergence. With our nonactivating panel KEY, the
    // system-wide focused element should point at the panel field while the pid-targeted
    // read still finds the host field. Logging both is the whole point of the extended gate.
    var panelWasKey = false
    var systemWideRole: String? = nil   // expected: our panel's AXTextField
    var pidRole: String? = nil          // expected: the host app's focused field
    var beforeLen: Int? = nil
    var afterLen: Int? = nil
}

/// Decide the path the way the real app must: read first, then choose.
/// Critically enforces the CLOBBER BAN (DESIGN §2.3): never value-set a non-empty field.
func choosePath(_ el: AXUIElement?, evidence ev: inout Evidence) -> PastePath {
    guard let el = el else {
        logAX("Focused element unreadable (typical Electron) → Strategy A directly.")
        return .aClipboard
    }
    ev.focusedReadable = true
    ev.role = axString(el, kAXRoleAttribute as String)
    ev.selectedTextSettable = axSettable(el, kAXSelectedTextAttribute as String)
    ev.valueSettable = axSettable(el, kAXValueAttribute as String)
    ev.hasSelectedTextRange = axHasAttribute(el, kAXSelectedTextRangeAttribute as String)
    let currentValue = axString(el, kAXValueAttribute as String)
    ev.fieldWasEmpty = currentValue.map { $0.isEmpty }

    logAX("role=\(ev.role ?? "?") selText-settable=\(ev.selectedTextSettable) "
        + "value-settable=\(ev.valueSettable) selRange=\(ev.hasSelectedTextRange) "
        + "empty=\(ev.fieldWasEmpty.map(String.init) ?? "?")")

    if ev.selectedTextSettable {
        return .bSelectedText                       // preferred: non-destructive insert at caret
    }
    if ev.valueSettable && ev.fieldWasEmpty == true {
        return .bValueSet                           // safe: nothing to clobber
    }
    // value-settable but non-empty (or emptiness unknown) → CLOBBER BAN → never value-set.
    if ev.valueSettable {
        logAX("value-settable but field is non-empty/unknown → CLOBBER BAN (§2.3) → Strategy A.")
    }
    return .aClipboard
}

// MARK: - Strategy B: Accessibility direct write

func strategyB_selectedText(_ el: AXUIElement, _ text: String) -> Bool {
    let err = AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString)
    logAX("kAXSelectedTextAttribute write returned: AXError \(err.rawValue) "
        + "(\(err == .success ? "success" : "fail")) — return code is NOT proof; read-back decides.")
    return err == .success
}

func strategyB_valueSet(_ el: AXUIElement, _ text: String) -> Bool {
    let err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFString)
    logAX("kAXValueAttribute write returned: AXError \(err.rawValue) "
        + "(\(err == .success ? "success" : "fail")) — read-back decides.")
    return err == .success
}

// MARK: - Strategy A: clipboard + synthesized ⌘V (fallback), always restores

func strategyA_clipboardPaste(_ text: String, evidence ev: inout Evidence) -> Bool {
    let pb = NSPasteboard.general

    // Snapshot EVERY item/type so we can restore exactly (not just the string).
    let saved: [[String: Data]] = pb.pasteboardItems?.map { item in
        var dict: [String: Data] = [:]
        for type in item.types { if let d = item.data(forType: type) { dict[type.rawValue] = d } }
        return dict
    } ?? []
    logCB("Clipboard snapshot saved (\(saved.count) item(s)).")

    let baselineChange = pb.changeCount
    pb.clearContents()
    pb.setString(text, forType: .string)
    guard pb.changeCount > baselineChange else {
        logCB("Pasteboard changeCount did not advance after setString — aborting, restoring.")
        restoreClipboard(saved); return false
    }
    let ourChange = pb.changeCount
    logCB("Marker placed on clipboard (changeCount \(baselineChange) → \(ourChange)).")

    // Synthesize ⌘V. 'v' is virtual keycode 9.
    let vKey: CGKeyCode = 9
    guard let src = CGEventSource(stateID: .combinedSessionState),
          let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
          let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
    else {
        logCB("Failed to build CGEvents. Restoring clipboard.")
        restoreClipboard(saved); return false
    }
    keyDown.flags = .maskCommand
    keyUp.flags   = .maskCommand
    keyDown.post(tap: .cgAnnotatedSessionEventTap)
    keyUp.post(tap: .cgAnnotatedSessionEventTap)
    logCB("CGEvent ⌘V sent.")

    // Honest note: a paste READS the pasteboard, it does not bump changeCount, so there is
    // no positive "target consumed it" signal. We give a bounded grace period (120ms ceiling,
    // DESIGN §2.4) polled in small steps, and we bail early only if SOMETHING ELSE clobbers
    // our marker (changeCount jumps past ours) — which is the app-switch-contention case the
    // real app must survive. Then restore.
    let ceilingMicros: useconds_t = 120_000
    let stepMicros: useconds_t = 10_000
    var waited: useconds_t = 0
    while waited < ceilingMicros {
        if pb.changeCount != ourChange {
            logCB("Pasteboard changed under us (changeCount now \(pb.changeCount)) — restoring immediately.")
            break
        }
        usleep(stepMicros)
        waited += stepMicros
    }
    restoreClipboard(saved)
    return true
}

func restoreClipboard(_ saved: [[String: Data]]) {
    let pb = NSPasteboard.general
    pb.clearContents()
    let items: [NSPasteboardItem] = saved.map { dict in
        let item = NSPasteboardItem()
        for (type, data) in dict { item.setData(data, forType: .init(type)) }
        return item
    }
    if !items.isEmpty { pb.writeObjects(items) }
    logCB("Clipboard restored.")
}

// MARK: - Evidence dump

func printEvidence(_ ev: Evidence, target: String) {
    print("")
    print("──────────────── EVIDENCE DUMP ────────────────")
    print("  target (eyeball)     : \(target)")
    print("  panel was KEY        : \(ev.panelWasKey ? "YES" : "NO")")
    print("  system-wide role     : \(ev.systemWideRole ?? "—")  (review D2: expect our panel field)")
    print("  pid-targeted role    : \(ev.pidRole ?? "—")  (review D1: expect host field)")
    print("  focused readable     : \(ev.focusedReadable)")
    print("  role                 : \(ev.role ?? "—")")
    print("  field len before→after: \(ev.beforeLen.map(String.init) ?? "?") → \(ev.afterLen.map(String.init) ?? "?")")
    print("  selText settable     : \(ev.selectedTextSettable)")
    print("  value settable       : \(ev.valueSettable)")
    print("  selRange present     : \(ev.hasSelectedTextRange)")
    print("  field was empty      : \(ev.fieldWasEmpty.map(String.init) ?? "unknown")")
    print("  chosen path          : \(ev.chosenPath?.rawValue ?? "—")")
    print("  strategy fired       : \(ev.strategyFired)")
    print("  READ-BACK confirmed  : \(ev.readBackConfirmed ? "YES ✅" : "NO ❌")")
    print("  read-back value      : \(ev.readBackValue.map { "\"\($0)\"" } ?? "<unreadable>")")
    print("  clipboard clean      : \(ev.clipboardClean.map { $0 ? "YES ✅" : "NO ❌" } ?? "n/a")")
    print("───────────────────────────────────────────────")
    print("  Paste this row into TASKS §Gate 0 for this target.")
    print("")
}
