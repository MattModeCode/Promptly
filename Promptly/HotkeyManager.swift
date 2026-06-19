import AppKit
import Carbon

protocol HotkeyManagerProtocol: AnyObject {
    var onHotkey: (() -> Void)? { get set }
}

final class HotkeyManager: HotkeyManagerProtocol {
    var onHotkey: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() { register() }

    private func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let hotKeyID = EventHotKeyID(signature: OSType(0x50524D50), id: 1) // 'PRMP'

        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onHotkey?() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        RegisterEventHotKey(49, UInt32(optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }
}
