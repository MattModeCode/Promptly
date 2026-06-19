// PasteProbe.swift — the spike. Prove the paste loop before any app code exists.
//
// Run (Apple Intel / x86_64):
//     arch -x86_64 swift PasteCore.swift PasteProbe.swift
// (The pure logic + strategies now live in Promptly/PasteCore.swift — one source of truth —
//  so this probe and the shipping PasteService share identical behavior. DESIGN §5.)
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
// The pure logic proven here is extracted VERBATIM into Promptly/PasteCore.swift, so the
// behavior proven here is the behavior that ships. Keep it honest.

import AppKit
import ApplicationServices

// The string we try to drop. Unique-ish so you can eyeball that it landed.
let marker = "PASTEPROBE_OK_\u{2713}"

// Seconds to switch to the target field before the probe fires.
let leadSeconds = 4

// MARK: - Key panel harness (review D2)
//
// The app does NOT paste into a bare focused field — it pastes while its OWN nonactivating
// panel is up and KEY (it has to be key to receive the filter keystrokes). That changes who
// the system-wide focused element is. The original spike never opened a panel, so it proved
// an easier condition than the app runs in. This harness reproduces the real condition: a
// `.nonactivatingPanel` that becomes key, hosting a dummy search field, before we probe.
//
// Caveat (be honest): this runs from a plain `swift` script, not a bundled LSUIElement app.
// Nonactivating/key behavior is faithful enough to catch the system-wide-vs-pid divergence,
// but the FINAL proof is still the bundled app under run.sh. If the pid-targeted read finds
// the host field here while system-wide finds the panel, the mechanism is sound.

func makeKeyProbePanel() -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 44),
        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
        backing: .buffered, defer: false)
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    let field = NSTextField(string: "")
    field.placeholderString = "Search prompts… (probe panel)"
    field.frame = NSRect(x: 12, y: 8, width: 456, height: 28)
    panel.contentView?.addSubview(field)
    panel.center()
    panel.orderFrontRegardless()
    panel.makeKey()
    panel.makeFirstResponder(field)
    return panel
}

// MARK: - Probe run

func runProbe() {
    // An accessory app: no Dock icon, can show a nonactivating key panel without stealing
    // activation — the same posture as the real LSUIElement app.
    NSApplication.shared.setActivationPolicy(.accessory)

    guard ensureAccessibilityTrust() else { exit(1) }

    let before = NSPasteboard.general.string(forType: .string)
    logMain("Clipboard before: \(before.map { "\"\($0)\"" } ?? "<empty/non-string>")")

    logMain("Click into a text field in your target app. Firing in \(leadSeconds)s...")
    for remaining in stride(from: leadSeconds, through: 1, by: -1) {
        logMain("  \(remaining)...")
        sleep(1)
    }

    // 1. Capture the host app + pid BEFORE any panel appears (invariant 1).
    let app = captureFrontmostApp()
    let targetName = app?.localizedName ?? "?"
    let pid = app?.processIdentifier

    var ev = Evidence()

    // 2. Read the host field's BEFORE length via the pid-targeted element (anchor for read-back).
    if let pid = pid, let hostField = copyFocusedElement(forPid: pid) {
        ev.beforeLen = axValueLength(hostField)
    }

    // 3. Bring up the KEY panel — now we are in the app's real runtime condition.
    let panel = makeKeyProbePanel()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))   // let it become key + draw
    ev.panelWasKey = panel.isKeyWindow
    logMain("Probe panel is key: \(ev.panelWasKey). (Review D2: host field must still be reachable by pid.)")

    // 4. Log the DIVERGENCE: system-wide focus (now the panel) vs pid-targeted (still the host).
    let systemWide = copyFocusedElement()
    ev.systemWideRole = systemWide.flatMap { axString($0, kAXRoleAttribute as String) }
    logAX("system-wide focused role = \(ev.systemWideRole ?? "—")  (expect OUR panel field — DON'T paste here)")

    guard let pid = pid else {
        logMain("No captured pid — cannot target the host app. Aborting.")
        return
    }
    let focused = copyFocusedElement(forPid: pid)        // <-- the mechanism the app extracts
    ev.pidRole = focused.flatMap { axString($0, kAXRoleAttribute as String) }
    logAX("pid-targeted focused role = \(ev.pidRole ?? "—")  (expect the HOST field — paste HERE)")

    logMain("Attempting paste of: \"\(marker)\" into pid \(pid) (\(targetName))")
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

    // READ-BACK (anchored): the only acceptable proof the marker landed (DESIGN §2.1, review A3).
    if let el = focused {
        let rb = readBackConfirms(el, inserted: marker, beforeLen: ev.beforeLen)
        ev.readBackConfirmed = rb.confirmed
        ev.readBackValue = rb.value
        ev.afterLen = rb.afterLen
        logMain("READ-BACK: marker \(rb.confirmed ? "CONFIRMED by anchor ✅" : "NOT confirmed ❌") "
            + "(len \(rb.beforeLen.map(String.init) ?? "?")→\(rb.afterLen.map(String.init) ?? "?"), "
            + "needed +\(marker.count)).")
        if rb.value == nil {
            logMain("  (focused element value unreadable — typical of Electron on the A path;")
            logMain("   for known-hostile targets, fall back to eyeballing the field + a clean clipboard.)")
        }
    } else {
        logMain("READ-BACK: pid-targeted focused element was unreadable — cannot confirm programmatically.")
        logMain("  Eyeball the target field; a clean-clipboard A paste is the acceptable pass here.")
    }

    // Verify the clipboard came back unchanged (HARD RULE: never leave it mutated).
    let after = NSPasteboard.general.string(forType: .string)
    let clean = (before == after)
    ev.clipboardClean = clean
    logMain("Clipboard after: \(after.map { "\"\($0)\"" } ?? "<empty/non-string>")")
    logMain("Clipboard clean (== before)? \(clean ? "YES ✅" : "NO ❌")")

    panel.orderOut(nil)
    printEvidence(ev, target: targetName)
    logMain("Now eyeball the target field too: did \"\(marker)\" land where your cursor was?")
}

runProbe()
