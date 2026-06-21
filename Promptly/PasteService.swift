import AppKit
import ApplicationServices
import os.log

private let log = OSLog(subsystem: "com.promptly.app", category: "paste")

enum PasteResult {
    case success
    case failure(reason: String)
}

struct PasteService {
    /// Paste `text` into the captured app. `cursorOffset` (a UTF-16 offset into `text`,
    /// from a `{{cursor}}` token — DESIGN §2.5) places the caret precisely on the B path;
    /// the A fallback can't honor it and leaves the caret at end-of-paste.
    static func paste(_ text: String, into captured: CapturedApp,
                      cursorOffset: Int? = nil) -> PasteResult {
        dispatchPrecondition(condition: .onQueue(.main))

        let trusted = AXIsProcessTrusted()
        os_log("AX status: %{public}@", log: log, type: .info, trusted ? "trusted" : "not trusted")
        guard trusted else { return .failure(reason: "Accessibility not granted") }

        guard let element = copyFocusedElement(forPid: captured.pid) else {
            os_log("No focused element for pid %d — falling back to strategy A", log: log, type: .info, captured.pid)
            var evidence = Evidence()
            let ok = strategyA_clipboardPaste(text, evidence: &evidence)
            os_log("Strategy A result: %{public}@", log: log, type: .info, ok ? "success" : "failure")
            return ok ? .success : .failure(reason: "Clipboard paste failed")
        }

        var evidence = Evidence()
        // Anchor read-back on the BEFORE length (DESIGN §2.1): a selected-text insert into a
        // non-empty field is confirmed by a +text.count delta, so we must read len first.
        evidence.beforeLen = axValueLength(element)
        // Caret start BEFORE the insert — needed to place {{cursor}} on the selected-text path,
        // where the prompt is dropped at the existing caret (not at offset 0).
        let caretStart = selectedRangeLocation(element)
        let path = choosePath(element, evidence: &evidence)
        os_log("Strategy chosen: %{public}@", log: log, type: .info, String(describing: path))

        let ok: Bool
        switch path {
        case .bSelectedText:
            ok = strategyB_selectedText(element, text)
        case .bValueSet:
            ok = strategyB_valueSet(element, text)
        case .aClipboard:
            ok = strategyA_clipboardPaste(text, evidence: &evidence)
        }

        // Read-back is the only proof the marker landed (DESIGN §2.1). A `.success`
        // return from an AX set means nothing on WebKit/Electron shims.
        let confirmed: Bool
        switch path {
        case .bSelectedText, .bValueSet:
            let rb = readBackConfirms(element, inserted: text, beforeLen: evidence.beforeLen)
            confirmed = rb.confirmed
            os_log("Read-back: %{public}@", log: log, type: .info, confirmed ? "confirmed" : "NOT confirmed")
            // {{cursor}} placement is a B-path-only precise feature (DESIGN §2.5). Best-effort:
            // a failure to move the caret never fails the paste — the text already landed.
            if confirmed, let offset = cursorOffset {
                let base = (path == .bValueSet) ? 0 : (caretStart ?? 0)
                placeCaret(element, at: base + offset)
            }
        case .aClipboard:
            // Strategy A pastes via synthesized ⌘V into a possibly-unreadable target; the
            // success signal is a clean clipboard + the paste having been sent. The caret
            // lands at end-of-paste; {{cursor}} can't be honored here (DESIGN §2.5).
            confirmed = ok
        }

        os_log("Paste result: %{public}@", log: log, type: .info, (ok && confirmed) ? "success" : "failure")
        os_log("Clipboard restore: %{public}@", log: log, type: .info,
               (evidence.clipboardClean ?? true) ? "clean" : "dirty")

        if path == .aClipboard {
            return ok ? .success : .failure(reason: "Clipboard paste failed")
        }
        return (ok && confirmed) ? .success : .failure(reason: "Paste not confirmed via \(path)")
    }

    // MARK: - Caret placement (B path only — {{cursor}}, DESIGN §2.5)

    /// The current caret location (start of the selected range) of a focused element, or nil
    /// if the element doesn't expose `kAXSelectedTextRange`. App-level read, not in PasteCore.
    private static func selectedRangeLocation(_ el: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.location
    }

    /// Collapse the selection to a zero-length caret at `location`. Best-effort: a silent
    /// no-op (e.g. an element that ignores range writes) is acceptable — the text landed.
    private static func placeCaret(_ el: AXUIElement, at location: Int) {
        var range = CFRange(location: max(0, location), length: 0)
        guard let value = AXValueCreate(.cfRange, &range) else { return }
        let err = AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value)
        os_log("Caret placement at %d: %{public}@", log: log, type: .info,
               location, err == .success ? "ok" : "ignored")
    }
}
