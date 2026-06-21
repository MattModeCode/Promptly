import AppKit

// ThemedControls.swift — Stage 10 "Inset Slate" monochrome controls for the Library window.
//
// One source of truth for the dark-theme look used across the editor: a flat, layer-backed button,
// a pin-chip toggle, a themed popup, and the New-folder sheet. All monochrome (DESIGN: "a keyboard,
// not a piano") — the only chroma is the functional red on a `.destructive` button. Values match the
// approved "Inset Slate" mockup (fill white@6%, primary white@13%, border white@14/22%, radius 6).
//
// OFF-PASTE-PATH: these are Library-only chrome. They never touch Capture / PanelController.present /
// PasteService, so the never-steal-focus invariant (DESIGN §5.1) is unaffected.

// MARK: - Editable themed text field (fixes the dead-field + top-sliver bugs)

/// Mirrors `FilterField` (PanelController) by setting the cell via `cellClass` rather than assigning
/// `f.cell = VCenterTextFieldCell()`. A bare `init()` cell defaults to non-editable/non-selectable —
/// which is exactly why the old `libraryTextField()` fields couldn't be clicked into (Bug A). Going
/// through `cellClass` lets AppKit build an editable cell the same way the working HUD field does.
final class LibraryField: NSTextField {
    override class var cellClass: AnyClass? {
        get { VCenterTextFieldCell.self }
        set {}
    }
}

// MARK: - ThemedButton

class ThemedButton: NSButton {
    enum Style { case standard, primary, destructive, ghost }

    var style: Style { didSet { applyStyle() } }
    private var hovering = false
    private var pressed = false
    private var focused = false
    private var tracking: NSTrackingArea?

    private static let red = NSColor(red: 0xef/255, green: 0x44/255, blue: 0x44/255, alpha: 1)

    init(title: String, style: Style = .standard, target: AnyObject?, action: Selector?) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        applyStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    // Colors — monochrome; destructive is the one functional chroma.
    private func fillColor() -> NSColor {
        switch style {
        case .ghost: return NSColor(white: 1, alpha: hovering ? 0.05 : 0.0)
        case .standard: return NSColor(white: 1, alpha: (hovering ? 0.10 : 0.06) - (pressed ? 0.03 : 0))
        case .primary: return NSColor(white: 1, alpha: (hovering ? 0.17 : 0.13) - (pressed ? 0.03 : 0))
        case .destructive: return Self.red.withAlphaComponent(hovering ? 0.10 : 0.05)
        }
    }
    private func borderColor() -> NSColor {
        if focused { return NSColor(white: 1, alpha: 0.40) }
        switch style {
        case .standard, .ghost: return NSColor(white: 1, alpha: 0.14)
        case .primary: return NSColor(white: 1, alpha: 0.22)
        case .destructive: return Self.red.withAlphaComponent(0.45)
        }
    }
    private func textColor() -> NSColor {
        switch style {
        case .destructive: return Self.red
        case .primary: return .white
        default: return Palette.primary
        }
    }

    /// `internal` so `PinChipButton` can re-apply after flipping its on/off look.
    func applyStyle() {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Palette.mono(12),
            .foregroundColor: textColor(),
            .paragraphStyle: p,
        ])
        layer?.backgroundColor = fillColor().cgColor
        layer?.borderColor = borderColor().cgColor
        alphaValue = isEnabled ? 1.0 : 0.4
        invalidateIntrinsicContentSize()
    }

    override var isEnabled: Bool { didSet { applyStyle() } }

    override var intrinsicContentSize: NSSize {
        let textW = attributedTitle.length > 0
            ? attributedTitle.size().width
            : NSAttributedString(string: title, attributes: [.font: Palette.mono(12)]).size().width
        let iconW: CGFloat = image != nil ? 18 : 0
        return NSSize(width: ceil(textW) + iconW + 26, height: 28)
    }

    // Hover
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; applyStyle() }
    override func mouseExited(with event: NSEvent) { hovering = false; applyStyle() }

    // Pressed (super.mouseDown runs the tracking loop and fires the action on mouse-up-inside)
    override func mouseDown(with event: NSEvent) {
        pressed = true; applyStyle()
        super.mouseDown(with: event)
        pressed = false; applyStyle()
    }

    // Keyboard focus ring (custom, since focusRingType is .none)
    override var canBecomeKeyView: Bool { true }
    override func becomeFirstResponder() -> Bool { focused = true; applyStyle(); return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { focused = false; applyStyle(); return super.resignFirstResponder() }
}

// MARK: - PinChipButton

/// A self-toggling chip: outline "Pin" when off, brighter-filled "Pinned" when on (monochrome — the
/// fill jump is the signal, no accent color). Replaces the native `NSSwitch`.
final class PinChipButton: ThemedButton {
    var isOn: Bool = false { didSet { applyChip() } }

    init() {
        super.init(title: "Pin", style: .standard, target: nil, action: nil)
        target = self
        action = #selector(flip)
        imagePosition = .imageLeading
        imageHugsTitle = true
        applyChip()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func flip() { isOn.toggle() }

    private func applyChip() {
        title = isOn ? "Pinned" : "Pin"
        style = isOn ? .primary : .standard   // triggers applyStyle()
        if #available(macOS 11.0, *) {
            let symbol = isOn ? "pin.fill" : "pin"
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: isOn ? "Pinned" : "Pin") {
                img.isTemplate = true
                image = img
                contentTintColor = isOn ? .white : Palette.secondary
            }
        }
        applyStyle()
        setAccessibilityLabel(isOn ? "Pinned" : "Pin")
    }
}

// MARK: - ThemedPopUp

/// Borderless, layer-backed popup face matching the input boxes. Item titles are themed in
/// `themeItems()`; the dropdown menu itself renders dark via the window's `.darkAqua` appearance.
final class ThemedPopUp: NSPopUpButton {
    init() {
        super.init(frame: .zero, pullsDown: false)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        font = Palette.mono(12)
        contentTintColor = Palette.primary
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Re-color every item in mono/primary (call after rebuilding the menu).
    func themeItems() {
        for item in itemArray {
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [
                .font: Palette.mono(12), .foregroundColor: Palette.primary,
            ])
        }
    }
}

// MARK: - NewFolderSheet

/// Themed replacement for the old native `NSAlert` folder prompt (DESIGN: keep the Library one
/// cohesive surface). Slides down as a sheet on the host window, returns the trimmed name (or nil)
/// through `completion`. Create is disabled while the field is blank; ⏎ creates, ⎋ cancels.
final class NewFolderSheet: NSObject, NSTextFieldDelegate {
    private var sheet: NSWindow!
    private let field = LibraryField()
    private var createButton: ThemedButton!
    private var completion: ((String?) -> Void)?

    // Self-retain for the sheet's lifetime so the caller doesn't have to hold it.
    private static var active: NewFolderSheet?

    func present(over host: NSWindow, completion: @escaping (String?) -> Void) {
        self.completion = completion
        NewFolderSheet.active = self
        build()
        host.beginSheet(sheet, completionHandler: nil)
        sheet.makeFirstResponder(field)
    }

    private func build() {
        let pad: CGFloat = 20
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                         styleMask: [.titled], backing: .buffered, defer: false)
        sheet.appearance = NSAppearance(named: .darkAqua)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 150))
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.panelBG.cgColor
        sheet.contentView = content

        let header = NSTextField(labelWithString: "New folder")
        header.font = Palette.monoMedium(14)
        header.textColor = Palette.primary
        header.backgroundColor = .clear
        header.isBordered = false
        header.translatesAutoresizingMaskIntoConstraints = false

        field.font = Palette.mono(13)
        field.textColor = Palette.primary
        field.placeholderAttributedString = NSAttributedString(
            string: "Folder name", attributes: [.font: Palette.mono(13), .foregroundColor: Palette.footer])
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        field.wantsLayer = true
        field.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        field.layer?.cornerRadius = 5
        field.layer?.masksToBounds = true
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        field.delegate = self

        let cancelButton = ThemedButton(title: "Cancel", style: .ghost, target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"   // Esc
        createButton = ThemedButton(title: "Create", style: .primary, target: self, action: #selector(createTapped))
        createButton.keyEquivalent = "\r"        // ↵ default
        createButton.isEnabled = false

        [header, field, cancelButton, createButton].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            field.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            field.heightAnchor.constraint(equalToConstant: 30),

            createButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            createButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),
            cancelButton.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
        ])
    }

    func controlTextDidChange(_ obj: Notification) {
        createButton.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @objc private func createTapped() {
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        finish(with: name.isEmpty ? nil : name)
    }
    @objc private func cancelTapped() { finish(with: nil) }

    private func finish(with result: String?) {
        if let host = sheet.sheetParent { host.endSheet(sheet) }
        completion?(result)
        completion = nil
        NewFolderSheet.active = nil
    }
}

// MARK: - ConfirmSheet

/// Themed replacement for a destructive `NSAlert` — keeps the Library one cohesive surface, like
/// `NewFolderSheet`. Slides down as a sheet on the host window with a title, a message line, and a
/// Cancel / confirm button pair, returning the user's choice through `completion`. ⏎ confirms
/// (preserving the old NSAlert's default-Delete behavior), ⎋ cancels. The confirm button defaults
/// to `.destructive` — the custom themed red Delete button.
final class ConfirmSheet: NSObject {
    private var sheet: NSWindow!
    private var completion: ((Bool) -> Void)?

    // Self-retain for the sheet's lifetime so the caller doesn't have to hold it.
    private static var active: ConfirmSheet?

    func present(over host: NSWindow, title: String, message: String, confirmTitle: String,
                 confirmStyle: ThemedButton.Style = .destructive,
                 completion: @escaping (Bool) -> Void) {
        self.completion = completion
        ConfirmSheet.active = self
        build(title: title, message: message, confirmTitle: confirmTitle, confirmStyle: confirmStyle)
        host.beginSheet(sheet, completionHandler: nil)
    }

    private func build(title: String, message: String, confirmTitle: String, confirmStyle: ThemedButton.Style) {
        let pad: CGFloat = 20
        let width: CGFloat = 360
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 150),
                         styleMask: [.titled], backing: .buffered, defer: false)
        sheet.appearance = NSAppearance(named: .darkAqua)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 150))
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.panelBG.cgColor
        sheet.contentView = content

        let header = NSTextField(labelWithString: title)
        header.font = Palette.monoMedium(14)
        header.textColor = Palette.primary
        header.backgroundColor = .clear
        header.isBordered = false
        header.lineBreakMode = .byTruncatingTail
        header.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(labelWithString: message)
        body.font = Palette.mono(12)
        body.textColor = Palette.secondary
        body.backgroundColor = .clear
        body.isBordered = false
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 0
        body.setContentCompressionResistancePriority(.required, for: .vertical)
        body.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = ThemedButton(title: "Cancel", style: .ghost, target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"   // Esc
        let confirmButton = ThemedButton(title: confirmTitle, style: confirmStyle, target: self, action: #selector(confirmTapped))
        confirmButton.keyEquivalent = "\r"        // ↵ default

        [header, body, cancelButton, confirmButton].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            confirmButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            confirmButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),
            cancelButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: confirmButton.centerYAnchor),
        ])
    }

    @objc private func confirmTapped() { finish(with: true) }
    @objc private func cancelTapped() { finish(with: false) }

    private func finish(with result: Bool) {
        if let host = sheet.sheetParent { host.endSheet(sheet) }
        completion?(result)
        completion = nil
        ConfirmSheet.active = nil
    }
}
