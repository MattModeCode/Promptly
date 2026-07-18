import AppKit
import Carbon

protocol HotkeyManagerProtocol: AnyObject {
    /// ⌥Space by default — open the palette. User-rebindable via `rebindPalette`.
    var onHotkey: (() -> Void)? { get set }
    /// ⌥⇧Space — capture the current selection into a "save as prompt" sheet (Stage 5). Fixed.
    var onCaptureHotkey: (() -> Void)? { get set }
    /// Re-register the palette hotkey to a new combo and persist it. Only the palette hotkey is
    /// rebindable — the inverse-capture combo stays hardcoded.
    func rebindPalette(keyCode: UInt32, modifiers: UInt32)
    /// The palette hotkey as its menu glyph string (e.g. `⌥Space`), for the status-menu label.
    var paletteDisplayString: String { get }
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
    /// Shared Carbon signature ('PRMP') for both registrations — reused by `rebindPalette`.
    private let signature = OSType(0x50524D50)

    // The palette combo is user-rebindable and persisted, so it survives the AX-grant relaunch
    // (reloaded here in `init`). Defaults to ⌥Space (keycode 49, optionKey) on first run. The
    // inverse-capture combo stays hardcoded (⌥⇧Space).
    private var paletteKeyCode: UInt32
    private var paletteModifiers: UInt32
    private let defaults = UserDefaults(suiteName: "com.promptly.app")
    private static let keyCodeDefaultsKey = "paletteKeyCode"
    private static let modifiersDefaultsKey = "paletteModifiers"
    private static let defaultPaletteKeyCode: UInt32 = 49          // Space
    private static let defaultPaletteModifiers = UInt32(optionKey) // ⌥

    init() {
        (paletteKeyCode, paletteModifiers) = Self.loadPaletteCombo(from: defaults)
        register()
    }

    /// Reads the persisted palette combo, defaulting to ⌥Space when unset. Both keys are written
    /// together by `rebindPalette`, so presence is checked via `object(forKey:)` — `integer(forKey:)`
    /// returns 0 for an unset key, and 0 is a real keycode ("A"). A stored combo missing a ⌘/⌥/⌃
    /// modifier is rejected at this boundary: registering a bare key would hijack normal typing.
    private static func loadPaletteCombo(from defaults: UserDefaults?) -> (keyCode: UInt32, modifiers: UInt32) {
        guard let d = defaults,
              d.object(forKey: keyCodeDefaultsKey) != nil,
              d.object(forKey: modifiersDefaultsKey) != nil else {
            return (defaultPaletteKeyCode, defaultPaletteModifiers)
        }
        let code = UInt32(truncatingIfNeeded: d.integer(forKey: keyCodeDefaultsKey))
        let mods = UInt32(truncatingIfNeeded: d.integer(forKey: modifiersDefaultsKey))
        guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            return (defaultPaletteKeyCode, defaultPaletteModifiers)
        }
        return (code, mods)
    }

    private func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

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

        // The palette — user-rebindable combo (defaults to ⌥Space). Kept in `paletteRef` so
        // `rebindPalette` can unregister it.
        RegisterEventHotKey(paletteKeyCode, paletteModifiers,
                            EventHotKeyID(signature: signature, id: paletteHotKeyID),
                            GetApplicationEventTarget(), 0, &paletteRef)
        // ⌥⇧Space (keycode 49, optionKey|shiftKey) — inverse capture (hardcoded).
        RegisterEventHotKey(49, UInt32(optionKey | shiftKey),
                            EventHotKeyID(signature: signature, id: captureHotKeyID),
                            GetApplicationEventTarget(), 0, &captureRef)
    }

    /// Re-register the palette hotkey to a new combo and persist it (so it survives the AX-grant
    /// relaunch, which reloads from `defaults` in `init`). Unregisters the old palette hot key and
    /// re-registers under the SAME id/signature/target, so the shared Carbon event handler — which
    /// dispatches by hot-key id and is combo-agnostic — keeps routing it without reinstallation.
    func rebindPalette(keyCode: UInt32, modifiers: UInt32) {
        if let ref = paletteRef { UnregisterEventHotKey(ref); paletteRef = nil }
        paletteKeyCode = keyCode
        paletteModifiers = modifiers
        defaults?.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults?.set(Int(modifiers), forKey: Self.modifiersDefaultsKey)
        RegisterEventHotKey(keyCode, modifiers,
                            EventHotKeyID(signature: signature, id: paletteHotKeyID),
                            GetApplicationEventTarget(), 0, &paletteRef)
    }

    /// The palette hotkey as its menu glyph string (e.g. `⌥Space`), for the status-menu label.
    var paletteDisplayString: String {
        Self.displayString(keyCode: paletteKeyCode, modifiers: paletteModifiers)
    }

    // MARK: - Display + modifier mapping (pure, testable)

    /// Renders a Carbon keycode + modifier bitmask as its menu-style glyph string, e.g. `⌥Space`
    /// or `⇧⌘K`. Modifiers always render in the canonical macOS order ⌃⌥⇧⌘, regardless of the
    /// order their bits were OR'd in, and an unmapped keycode falls back to `key<code>` so a gap
    /// in the table is visible, not blank. Pure so the Tier A test needs no event tap.
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { out += "⌘" }
        out += keyName(keyCode)
        return out
    }

    /// Maps Cocoa modifier flags (as `NSEvent` delivers them) to the Carbon modifier bitmask
    /// `RegisterEventHotKey` expects — the inverse of what `displayString` reads back.
    static func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if cocoa.contains(.control) { mods |= UInt32(controlKey) }
        if cocoa.contains(.option)  { mods |= UInt32(optionKey) }
        if cocoa.contains(.shift)   { mods |= UInt32(shiftKey) }
        if cocoa.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    /// Menu name/glyph for a Carbon virtual keycode — Space plus the ANSI letter and digit keys,
    /// enough for a ⌘-hotkey editor. Unmapped keys fall back to `key<code>`.
    private static func keyName(_ code: UInt32) -> String {
        keyNames[code] ?? "key\(code)"
    }

    /// ANSI virtual-keycode → label. Values are the standard macOS `kVK_ANSI_*` / `kVK_Space`
    /// constants (HIToolbox `Events.h`).
    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
    ]

    deinit {
        if let ref = paletteRef { UnregisterEventHotKey(ref) }
        if let ref = captureRef { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }
}
