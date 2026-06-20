import AppKit
import Carbon

protocol HotkeyManagerProtocol: AnyObject {
    /// ⌥Space — open the palette.
    var onHotkey: (() -> Void)? { get set }
    /// ⌥⇧Space — capture the current selection into a "save as prompt" sheet (Stage 5).
    var onCaptureHotkey: (() -> Void)? { get set }
}

final class HotkeyManager: HotkeyManagerProtocol {
    var onHotkey: (() -> Void)?
    var onCaptureHotkey: (() -> Void)?

    private var paletteRef: EventHotKeyRef?
    private var captureRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    // Two registrations via the SAME Carbon mechanism (not a mechanism change — that stays
    // ask-first, CLAUDE.md Boundaries). Dispatched apart by hot-key id in the shared handler.
    private let paletteHotKeyID: UInt32 = 1
    private let captureHotKeyID: UInt32 = 2

    init() { register() }

    private func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let sig = OSType(0x50524D50) // 'PRMP'

        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let ptr = userData, let event = event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr else { return OSStatus(eventNotHandledErr) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
            let id = hkID.id
            DispatchQueue.main.async {
                if id == mgr.paletteHotKeyID { mgr.onHotkey?() }
                else if id == mgr.captureHotKeyID { mgr.onCaptureHotkey?() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        // ⌥Space (keycode 49, optionKey) — the palette.
        RegisterEventHotKey(49, UInt32(optionKey),
                            EventHotKeyID(signature: sig, id: paletteHotKeyID),
                            GetApplicationEventTarget(), 0, &paletteRef)
        // ⌥⇧Space (keycode 49, optionKey|shiftKey) — inverse capture.
        RegisterEventHotKey(49, UInt32(optionKey | shiftKey),
                            EventHotKeyID(signature: sig, id: captureHotKeyID),
                            GetApplicationEventTarget(), 0, &captureRef)
    }

    deinit {
        if let ref = paletteRef { UnregisterEventHotKey(ref) }
        if let ref = captureRef { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }
}
