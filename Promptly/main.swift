import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotkeyManager: HotkeyManager!
    var promptStore: PromptStore!
    var panelController: PanelController!
    var accessibilityWindow: NSWindow?
    var editorPanel: PromptEditorPanel?
    var axPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        registerFonts()

        promptStore = PromptStore()
        promptStore.load()
        promptStore.startWatching()

        panelController = PanelController()
        panelController.promptStore = promptStore
        panelController.onCommit = { [weak self] prompt, body in
            self?.handleCommit(prompt, body: body)
        }
        panelController.onDismiss = {}
        panelController.onEdit = { [weak self] prompt in self?.openEditor(editing: prompt) }

        setupStatusItem()

        hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkey = { [weak self] in self?.onHotkey() }

        axPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateAXStatusMenuItem()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func onHotkey() {
        guard AXIsProcessTrusted() else {
            showAccessibilityWindow()
            return
        }
        guard let captured = Capture.captureFrontmostApp() else { return }
        panelController.present(captured: captured)
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
        menu.addItem(NSMenuItem(title: "New Prompt…", action: #selector(newPrompt), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open prompts folder…", action: #selector(openPromptsFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Promptly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func axStatusTitle() -> String {
        AXIsProcessTrusted() ? "Accessibility: ✓ Granted" : "⚠ Accessibility: Not granted — Fix…"
    }

    func updateAXStatusMenuItem() {
        statusItem.menu?.item(withTag: 100)?.title = axStatusTitle()
        updateStatusIcon()
    }

    @objc private func rebindHotkey() {
        let alert = NSAlert()
        alert.messageText = "Hotkey rebinding"
        alert.informativeText = "Hotkey rebinding is coming in a future update."
        alert.runModal()
    }

    @objc private func newPrompt() { openEditor(editing: nil) }

    private func openEditor(editing prompt: Prompt? = nil) {
        let editor = PromptEditorPanel(editing: prompt)
        editor.onSave = { [weak self] name, keywords, body in
            self?.promptStore.save(name: name, keywords: keywords, body: body,
                                   filename: prompt?.filename ?? "")
        }
        editor.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        editorPanel = editor
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
}

// MARK: - Accessibility Permission Window

final class AccessibilityPermissionWindow: NSWindow {
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

        content.addSubview(titleLabel)
        content.addSubview(body)
        content.addSubview(btn)
        contentView = content
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
