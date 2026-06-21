import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotkeyManager: HotkeyManager!
    var promptStore: PromptStore!
    var panelController: PanelController!
    var accessibilityWindow: NSWindow?
    var libraryWindow: LibraryWindowController?
    var axPollTimer: Timer?
    /// Last-seen Accessibility trust, so we can spot the untrusted→trusted edge (see `refreshAXState`).
    private var axTrusted = false
    /// One-shot guard so the grant-relaunch fires exactly once per process.
    private var didScheduleRelaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        registerFonts()
        installEditMenu()

        promptStore = PromptStore()
        promptStore.load()
        promptStore.startWatching()

        panelController = PanelController()
        panelController.promptStore = promptStore
        panelController.onCommit = { [weak self] prompt, body in
            self?.handleCommit(prompt, body: body)
        }
        panelController.onDismiss = {}
        panelController.onEdit = { [weak self] prompt in self?.libraryWindowController().show(editing: prompt) }

        setupStatusItem()

        hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkey = { [weak self] in self?.onHotkey() }
        hotkeyManager.onCaptureHotkey = { [weak self] in self?.onCaptureHotkey() }

        // Auto-detect an Accessibility grant made while we're running. macOS posts this system-wide
        // distributed notification the instant AX settings change; the 2s poll is a fallback in case
        // it doesn't fire. On the untrusted→trusted edge we relaunch, because the grant isn't honored
        // by an already-running process — paste keeps failing until the app restarts.
        axTrusted = AXIsProcessTrusted()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(accessibilityChanged),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil)
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshAXState()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func onHotkey() {
        guard AXIsProcessTrusted() else {
            showAccessibilityWindow()
            return
        }
        if panelController.isPresented {
            panelController.dismiss()
            return
        }
        guard let captured = Capture.captureFrontmostApp() else { return }
        panelController.present(captured: captured)
    }

    /// ⌥⇧Space — inverse capture (Stage 5). Read the selection from the host app FIRST (while
    /// it is still frontmost), then open a pre-filled "save as prompt" sheet.
    private func onCaptureHotkey() {
        guard AXIsProcessTrusted() else {
            showAccessibilityWindow()
            return
        }
        guard let captured = Capture.captureFrontmostApp() else { return }
        let selection = Capture.captureSelection(pid: captured.pid) ?? ""
        libraryWindowController().showNewPrompt(initialBody: selection)
    }

    private func handleCommit(_ prompt: Prompt, body: String) {
        guard let captured = panelController.lastCaptured else { return }
        promptStore.recordUse(of: prompt)
        // Expand static tokens at paste time (DESIGN §8). Read the clipboard BEFORE pasting —
        // Strategy A clears+restores it, so {{clipboard}} must be snapshotted here, up front.
        // `body` already has any {{ask:…}} filled in by the panel's ask flow (Stage 4).
        let clipboard = NSPasteboard.general.string(forType: .string)
        let expansion = TokenEngine.expand(body, clipboard: clipboard, now: Date())
        let result = PasteService.paste(expansion.text, into: captured,
                                        cursorOffset: expansion.cursorOffset)
        switch result {
        case .success:
            panelController.dismissAfterSuccessfulPaste()
        case .failure(let reason):
            panelController.showFailure(message: "Couldn't paste — copied to clipboard instead")
            print("[Promptly] paste failure: \(reason)")
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.menu = buildMenu()
    }

    private func updateStatusIcon() {
        let trusted = AXIsProcessTrusted()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Promptly")
            button.image?.isTemplate = true
            button.alphaValue = trusted ? 1.0 : 0.4
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let axItem = NSMenuItem(title: axStatusTitle(), action: nil, keyEquivalent: "")
        axItem.tag = 100
        menu.addItem(axItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Hotkey: ⌥Space    Rebind…", action: #selector(rebindHotkey), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Library…", action: #selector(openLibrary), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "New Prompt…", action: #selector(newPrompt), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open prompts folder…", action: #selector(openPromptsFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Promptly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func axStatusTitle() -> String {
        AXIsProcessTrusted() ? "Accessibility: ✓ Granted" : "⚠ Accessibility: Not granted — Fix…"
    }

    @objc private func accessibilityChanged() {
        // The distributed notification can arrive on a background thread — hop to main.
        DispatchQueue.main.async { [weak self] in self?.refreshAXState(fromNotification: true) }
    }

    /// Re-reads live AX trust, refreshes the menubar icon + status menu, and — on the
    /// untrusted→trusted edge — relaunches so the new grant actually takes effect (an
    /// already-running process keeps failing to paste until it restarts). Driven by both the 2s
    /// poll and the `com.apple.accessibility.api` notification.
    func refreshAXState(fromNotification: Bool = false) {
        let trusted = AXIsProcessTrusted()
        statusItem.menu?.item(withTag: 100)?.title = axStatusTitle()
        updateStatusIcon()

        guard !didScheduleRelaunch else { return }
        let grantedNow = trusted && !axTrusted
        // Stale-read safeguard: some setups return a stale `false` to the running process even after
        // the grant. If the permission window is on screen (user is mid grant-flow) and an
        // AX-settings change just fired, treat it as our grant and relaunch anyway.
        let staleButLikelyGranted = fromNotification && !trusted && (accessibilityWindow?.isVisible ?? false)
        axTrusted = trusted
        if grantedNow || staleButLikelyGranted {
            relaunchForAccessibility()
        }
    }

    /// Relaunch ourselves so a just-granted Accessibility permission takes effect. Waits for this
    /// process to fully exit before reopening, so the old instance releases the Carbon hotkey before
    /// the new one registers it. Gated to a single untrusted→trusted edge, so it can't loop.
    private func relaunchForAccessibility() {
        didScheduleRelaunch = true
        (accessibilityWindow as? AccessibilityPermissionWindow)?.showGrantedState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let path = Bundle.main.bundlePath
            let pid = ProcessInfo.processInfo.processIdentifier
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "while /bin/kill -0 \(pid) >/dev/null 2>&1; do /bin/sleep 0.2; done; /usr/bin/open \"\(path)\""]
            try? task.run()
            NSApp.terminate(nil)
        }
    }

    @objc private func rebindHotkey() {
        let alert = NSAlert()
        alert.messageText = "Hotkey rebinding"
        alert.informativeText = "Hotkey rebinding is coming in a future update."
        alert.runModal()
    }

    @objc private func openLibrary() { libraryWindowController().showLibrary() }
    @objc private func newPrompt() { libraryWindowController().showNewPrompt() }

    /// Lazily created, reused — the Library window is a singleton surface (Stage 9).
    private func libraryWindowController() -> LibraryWindowController {
        if let existing = libraryWindow { return existing }
        let window = LibraryWindowController(promptStore: promptStore)
        window.onWillShow = { [weak self] in self?.panelController.dismiss() }
        libraryWindow = window
        return window
    }

    @objc private func openPromptsFolder() {
        NSWorkspace.shared.open(PromptStore.promptsDir)
    }

    func showAccessibilityWindow() {
        if let existing = accessibilityWindow, existing.isVisible { existing.makeKeyAndOrderFront(nil); return }
        let w = AccessibilityPermissionWindow()
        w.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        accessibilityWindow = w
    }

    private func registerFonts() {
        for name in ["JetBrainsMono-Regular", "JetBrainsMono-Medium"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// Root-cause fix for copy/paste: as a menu-bar (.accessory) app, Promptly never builds an
    /// `NSApp.mainMenu`. The status-bar dropdown (`buildMenu()`/`statusItem.menu`) is a
    /// different thing and supplies no Edit-menu key equivalents — without one, ⌘C/⌘V/⌘X have
    /// no key equivalent to dispatch through, so they silently do nothing in any text field
    /// anywhere in the app. This menu is never visually drawn (the app stays `.accessory`); it
    /// exists purely so AppKit's key-equivalent dispatch finds the standard selectors and routes
    /// them to the first responder, which `NSTextField`/`NSTextView` already implement natively.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}

// MARK: - Accessibility Permission Window

final class AccessibilityPermissionWindow: NSWindow {
    private var bodyLabel: NSTextField!
    private var actionButton: NSButton!

    init() {
        let w: CGFloat = 420, h: CGFloat = 230
        let rect = NSRect(x: 0, y: 0, width: w, height: h)
        super.init(contentRect: rect,
                   styleMask: [.titled, .closable],
                   backing: .buffered,
                   defer: false)
        title = "Promptly"
        center()
        isReleasedWhenClosed = false
        backgroundColor = NSColor(red: 0x0f/255, green: 0x0f/255, blue: 0x14/255, alpha: 1)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let mono13 = NSFont(name: "JetBrainsMono-Regular", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let primaryColor = NSColor(red: 0xe2/255, green: 0xe8/255, blue: 0xf0/255, alpha: 1)
        let secondaryColor = NSColor(red: 0x94/255, green: 0xa3/255, blue: 0xb8/255, alpha: 1)

        let titleLabel = label("Promptly", font: NSFont(name: "JetBrainsMono-Medium", size: 16) ?? mono13,
                          color: primaryColor, frame: NSRect(x: 40, y: h-60, width: w-80, height: 24))
        titleLabel.alignment = .center

        let body = label("To type prompts into other apps, Promptly\nneeds Accessibility access.\n\nIt never reads your screen, and your\nclipboard is always restored.",
                         font: mono13, color: secondaryColor, frame: NSRect(x: 40, y: h-160, width: w-80, height: 90))
        body.alignment = .center

        let btn = ghostButton(title: "Open System Settings →",
                              frame: NSRect(x: w/2 - 130, y: 28, width: 260, height: 32))
        btn.target = self
        btn.action = #selector(openSettings)
        bodyLabel = body
        actionButton = btn

        content.addSubview(titleLabel)
        content.addSubview(body)
        content.addSubview(btn)
        contentView = content
    }

    /// Swap to a confirmation state while the app relaunches to pick up the new grant
    /// (`AppDelegate.relaunchForAccessibility`).
    func showGrantedState() {
        bodyLabel.stringValue = "✓ Accessibility granted.\n\nRestarting Promptly…"
        actionButton.isHidden = true
    }

    private func label(_ text: String, font: NSFont, color: NSColor, frame: NSRect) -> NSTextField {
        let f = NSTextField(frame: frame)
        f.stringValue = text
        f.font = font
        f.textColor = color
        f.backgroundColor = .clear
        f.isBordered = false
        f.isEditable = false
        f.isSelectable = false
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 0
        return f
    }

    private func ghostButton(title: String, frame: NSRect) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.title = title
        btn.font = NSFont(name: "JetBrainsMono-Regular", size: 12)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.layer?.borderWidth = 1.5
        btn.layer?.borderColor = NSColor(white: 0.9, alpha: 0.25).cgColor
        btn.layer?.backgroundColor = NSColor.clear.cgColor
        btn.isBordered = false
        btn.contentTintColor = NSColor(red: 0xe2/255, green: 0xe8/255, blue: 0xf0/255, alpha: 1)
        return btn
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

// MARK: - Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
