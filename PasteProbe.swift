// PasteProbe.swift — the spike. Prove the paste loop before any app code exists.
//
// Run (Apple Intel / x86_64):
//     arch -x86_64 swift PasteProbe.swift
//
// What it does: gives you a few seconds to click into a text field in another
// app, then drops a marker string into wherever the cursor is. It does NOT blindly
// try B-then-A. It first READS the focused element, inspects what it supports, and
// CHOOSES the path from evidence (DESIGN §2.2 capability-probe decision table).
// After writing, it VERIFIES BY READ-BACK — re-reading the field and asserting the
// marker actually landed — never trusting a `.success` return (DESIGN §2.1). Every
// step narrates itself, and each run ends with a one-block evidence dump that is the
// empirical basis for the decision table.
//
// Targets to run this against (cover the full failure surface):
//     Terminal, Safari (WebKit), Xcode (Apple text)   <- must-pass (read-back confirmed)
//     VSCode (Electron), Notes (sandboxed)            <- known-hostile (clean-clipboard A is an acceptable pass)
//
// Exit criteria (TASKS §Gate 0):
//   must-pass     -> marker confirmed in-field BY READ-BACK and clipboard byte-identical after.
//   known-hostile -> at least a clean-clipboard clipboard-fallback paste; AX outcome logged as
//                    a known limitation. A silent failure that clobbers/loses clipboard blocks regardless.
//
// This file is the source of truth for PasteService: the app extracts it verbatim,
// so the behavior proven here is the behavior that ships. Keep it honest.

import AppKit
import ApplicationServices

// The string we try to drop. Unique-ish so you can eyeball that it landed.
let marker = "PASTEPROBE_OK_\u{2713}"

// Seconds to switch to the target field before the probe fires.
let leadSeconds = 4

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
func copyFocusedElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
    guard err == .success, let untyped = focusedRef else {
        logAX("Could not read focused element: AXError \(err.rawValue).")
        return nil
    }
    return (untyped as! AXUIElement)
}

// MARK: - Read-back verification (DESIGN §2.1 — the whole point)

/// After a write, re-read the field and assert the marker is actually present.
/// `.success` from a set call is NOT evidence; this is. Returns (confirmed, whatWeRead).
func readBackConfirms(_ el: AXUIElement, marker: String) -> (confirmed: Bool, value: String?) {
    // Prefer the full value; fall back to the current selection.
    let value = axString(el, kAXValueAttribute as String) ?? axString(el, kAXSelectedTextAttribute as String)
    guard let v = value else { return (false, nil) } // unreadable -> cannot confirm (a finding in itself)
    return (v.contains(marker), v)
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
    print("  focused readable     : \(ev.focusedReadable)")
    print("  role                 : \(ev.role ?? "—")")
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

// MARK: - Probe run

func runProbe() {
    guard ensureAccessibilityTrust() else { exit(1) }

    let before = NSPasteboard.general.string(forType: .string)
    logMain("Clipboard before: \(before.map { "\"\($0)\"" } ?? "<empty/non-string>")")

    logMain("Click into a text field in your target app. Firing in \(leadSeconds)s...")
    for remaining in stride(from: leadSeconds, through: 1, by: -1) {
        logMain("  \(remaining)...")
        sleep(1)
    }

    let app = captureFrontmostApp()
    let targetName = app?.localizedName ?? "?"

    var ev = Evidence()
    let focused = copyFocusedElement()

    logMain("Attempting paste of: \"\(marker)\"")
    let path = choosePath(focused, evidence: &ev)
    ev.chosenPath = path
    logMain("Capability probe chose: \(path.rawValue)")

    switch path {
    case .bSelectedText:
        ev.strategyFired = "B/selected-text"
        _ = strategyB_selectedText(focused!, marker)
    case .bValueSet:
        ev.strategyFired = "B/value-set"
        _ = strategyB_valueSet(focused!, marker)
    case .aClipboard:
        ev.strategyFired = "A/clipboard"
        _ = strategyA_clipboardPaste(marker, evidence: &ev)
    }

    // READ-BACK: the only acceptable proof the marker landed (DESIGN §2.1).
    if let el = focused {
        let rb = readBackConfirms(el, marker: marker)
        ev.readBackConfirmed = rb.confirmed
        ev.readBackValue = rb.value
        logMain("READ-BACK: marker \(rb.confirmed ? "CONFIRMED in field ✅" : "NOT found ❌").")
        if rb.value == nil {
            logMain("  (focused element value unreadable — typical of Electron on the A path;")
            logMain("   for known-hostile targets, fall back to eyeballing the field + a clean clipboard.)")
        }
    } else {
        logMain("READ-BACK: focused element was unreadable — cannot confirm programmatically.")
        logMain("  Eyeball the target field; a clean-clipboard A paste is the acceptable pass here.")
    }

    // Verify the clipboard came back unchanged (HARD RULE: never leave it mutated).
    let after = NSPasteboard.general.string(forType: .string)
    let clean = (before == after)
    ev.clipboardClean = clean
    logMain("Clipboard after: \(after.map { "\"\($0)\"" } ?? "<empty/non-string>")")
    logMain("Clipboard clean (== before)? \(clean ? "YES ✅" : "NO ❌")")

    printEvidence(ev, target: targetName)
    logMain("Now eyeball the target field too: did \"\(marker)\" land where your cursor was?")
}

runProbe()
