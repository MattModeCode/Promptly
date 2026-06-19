import AppKit
import os.log

private let log = OSLog(subsystem: "com.promptly.app", category: "paste")

enum PasteResult {
    case success
    case failure(reason: String)
}

struct PasteService {
    static func paste(_ text: String, into captured: CapturedApp) -> PasteResult {
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
        case .aClipboard:
            // Strategy A pastes via synthesized ⌘V into a possibly-unreadable target; the
            // success signal is a clean clipboard + the paste having been sent.
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
}
