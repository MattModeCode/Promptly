import AppKit
import Carbon

// HotkeyCaptureWindow.swift — Stage 11 palette-hotkey rebinding surface.
//
// A small themed window that listens for a key combination and hands the captured combo back to
// its caller (main.swift → HotkeyManager.rebindPalette). Modeled on AccessibilityPermissionWindow:
// same Lightfall chrome, `Palette` tokens, `ThemedButton`. OFF the paste loop — this is a config
// surface, so it is allowed to take key focus (the never-steal-focus invariant only guards the
// palette/paste path, DESIGN §5.1).

// MARK: - Key-listening surface

/// Becomes first responder and turns each key press into a candidate palette combo:
/// `event.keyCode` + `HotkeyManager.carbonModifiers(from:)`. A combo is valid only if it carries at
/// least one of ⌘/⌥/⌃ — a bare key (or Shift-only, which is just normal typing) would hijack the
/// keyboard, so it is rejected and listening continues. Glyph rendering is reused from
/// `HotkeyManager.displayString`, never reimplemented.
final class HotkeyCaptureView: NSView {
    /// The combo just pressed, rendered for the live preview (whether or not it is valid).
    var onPreview: ((String) -> Void)?
    /// A press with no ⌘/⌥/⌃ — surface the hint and keep listening.
    var onInvalid: (() -> Void)?
    /// A valid combo — commit it and close.
    var onCapture: (((keyCode: UInt32, modifiers: UInt32)) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let modifiers = HotkeyManager.carbonModifiers(from: event.modifierFlags)
        onPreview?(HotkeyManager.displayString(keyCode: keyCode, modifiers: modifiers))
        // Require ⌘/⌥/⌃. Shift alone doesn't qualify — ⇧+key is ordinary typing.
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            onInvalid?()
            return   // swallow the event: no system beep, stay listening
        }
        onCapture?((keyCode: keyCode, modifiers: modifiers))
    }
}

// MARK: - Window

final class HotkeyCaptureWindow: NSWindow {
    /// Returns whether the combo was accepted (registered). `false` keeps the editor open so the
    /// user can pick another — a rebind that couldn't bind must not close as if it had worked.
    private let onCapture: ((keyCode: UInt32, modifiers: UInt32)) -> Bool
    private let currentCombo: String
    private let captureView = HotkeyCaptureView()
    private var previewLabel: NSTextField!
    private var hintLabel: NSTextField!

    init(current: String, onCapture: @escaping ((keyCode: UInt32, modifiers: UInt32)) -> Bool) {
        self.onCapture = onCapture
        self.currentCombo = current
        let w: CGFloat = 420, h: CGFloat = 236
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Promptly"
        titlebarAppearsTransparent = true
        center()
        isReleasedWhenClosed = false
        backgroundColor = Palette.surface0

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        // Capture surface — added first so it sits behind the visible chrome; transparent and
        // non-drawing, but the first responder that actually receives keyDown.
        captureView.frame = content.bounds
        captureView.onPreview = { [weak self] combo in
            self?.previewLabel.stringValue = combo
            self?.previewLabel.textColor = Palette.textPrimary
        }
        captureView.onInvalid = { [weak self] in
            self?.hintLabel.stringValue = "Must include ⌘, ⌥, or ⌃"
        }
        captureView.onCapture = { [weak self] combo in
            guard let self else { return }
            if self.onCapture(combo) {
                self.close()
            } else {
                // Registration failed (combo unavailable) — the manager rolled back to the old
                // hotkey; keep listening so the user can pick another instead of a dead close.
                self.hintLabel.stringValue = "That combo is unavailable — try another"
            }
        }
        content.addSubview(captureView)

        // Keyboard glyph (monochrome template — colour-free, off the paste loop).
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) {
            img.isTemplate = true
            let iv = NSImageView(image: img)
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            iv.contentTintColor = Palette.textSecondary
            iv.frame = NSRect(x: (w - 40) / 2, y: h - 58, width: 40, height: 30)
            content.addSubview(iv)
        }

        let titleLabel = label("Set palette hotkey", font: Palette.titleLgFont,
                               color: Palette.textPrimary,
                               frame: NSRect(x: 28, y: h - 96, width: w - 56, height: 24))
        titleLabel.alignment = .center

        previewLabel = label("Press a shortcut…", font: Palette.monoSemibold(22),
                             color: Palette.textSecondary,
                             frame: NSRect(x: 28, y: 84, width: w - 56, height: 30))
        previewLabel.alignment = .center
        previewLabel.setAccessibilityElement(true)
        previewLabel.setAccessibilityRole(.staticText)

        hintLabel = label("Now: \(currentCombo)", font: Palette.metaFont,
                         color: Palette.textSecondary,
                         frame: NSRect(x: 28, y: 58, width: w - 56, height: 16))
        hintLabel.alignment = .center

        let cancel = ThemedButton(title: "Cancel", style: .ghost, target: self, action: #selector(cancelTapped))
        cancel.translatesAutoresizingMaskIntoConstraints = true
        cancel.frame = NSRect(x: (w - 120) / 2, y: 18, width: 120, height: 30)
        cancel.keyEquivalent = "\u{1b}"   // Esc cancels (handled as a key equivalent before keyDown)

        [titleLabel, previewLabel, hintLabel, cancel].forEach { content.addSubview($0) }
        contentView = content
        initialFirstResponder = captureView
    }

    /// Force focus onto the capture surface whenever the window becomes key, so keyDown lands there
    /// regardless of what AppKit's key-view loop would otherwise pick.
    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(captureView)
    }

    @objc private func cancelTapped() { close() }

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
}
