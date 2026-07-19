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

    // Colors — strictly monochrome (Lightfall). The one high-emphasis CTA is an inverted near-white
    // plate; destructive reads as danger through luminance + confirmation + friction, never hue.
    private func fillColor() -> NSColor {
        switch style {
        case .ghost: return NSColor(white: 1, alpha: hovering ? 0.05 : 0.0)
        case .standard: return NSColor(white: 1, alpha: (hovering ? 0.10 : 0.06) - (pressed ? 0.03 : 0))
        case .primary:
            let a: CGFloat = pressed ? 0.86 : (hovering ? 1.0 : 0.94)
            return Palette.primaryButtonFill.withAlphaComponent(a)
        case .destructive: return NSColor(white: 1, alpha: hovering ? 0.10 : 0.05)
        }
    }
    private func borderColor() -> NSColor {
        if focused { return Palette.borderFocus }
        switch style {
        case .standard, .ghost: return Palette.borderDefault
        case .primary: return NSColor(white: 1, alpha: 0.0)   // the plate needs no outline
        case .destructive: return NSColor(white: 1, alpha: hovering ? 0.20 : 0.12)
        }
    }
    private func textColor() -> NSColor {
        switch style {
        case .destructive: return hovering ? .white : Palette.textPrimary
        case .primary: return Palette.surface0   // dark text on the near-white plate
        default: return Palette.textPrimary
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
    var onToggle: (() -> Void)?

    init() {
        super.init(title: "Pin", style: .standard, target: nil, action: nil)
        target = self
        action = #selector(flip)
        imagePosition = .imageLeading
        imageHugsTitle = true
        applyChip()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func flip() {
        isOn.toggle()
        onToggle?()
    }

    private func applyChip() {
        title = isOn ? "Pinned" : "Pin"
        style = isOn ? .primary : .standard   // triggers applyStyle()
        if #available(macOS 11.0, *) {
            let symbol = isOn ? "pin.fill" : "pin"
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: isOn ? "Pinned" : "Pin") {
                img.isTemplate = true
                image = img
                contentTintColor = isOn ? Palette.surface0 : Palette.secondary
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
        layer?.cornerRadius = Palette.Radius.control
        layer?.borderWidth = 1
        layer?.backgroundColor = Palette.surface2.cgColor
        layer?.borderColor = Palette.borderDefault.cgColor
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

    /// Doubles as a rename sheet via defaulted params (Stage 9) — `title`/`confirmTitle` relabel
    /// the header and confirm button, `initialValue` pre-seeds the field. Old "New folder" call
    /// sites keep working unchanged through the defaults. One sheet, never cloned.
    func present(over host: NSWindow, title: String = "New folder", initialValue: String = "",
                 confirmTitle: String = "Create", completion: @escaping (String?) -> Void) {
        self.completion = completion
        NewFolderSheet.active = self
        build(title: title, confirmTitle: confirmTitle)
        field.stringValue = initialValue
        refreshConfirmEnabled()   // reflect the seeded text (confirm stays disabled while blank)
        host.beginSheet(sheet, completionHandler: nil)
        sheet.makeFirstResponder(field)
    }

    private func build(title: String, confirmTitle: String) {
        let pad: CGFloat = 20
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                         styleMask: [.titled], backing: .buffered, defer: false)
        sheet.appearance = NSAppearance(named: .darkAqua)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 150))
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.surface2.cgColor
        sheet.contentView = content

        let header = NSTextField(labelWithString: title)
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
        field.layer?.backgroundColor = Palette.surface2.cgColor
        field.layer?.cornerRadius = Palette.Radius.control
        field.layer?.masksToBounds = true
        field.layer?.borderWidth = 1
        field.layer?.borderColor = Palette.borderDefault.cgColor
        field.delegate = self

        let cancelButton = ThemedButton(title: "Cancel", style: .ghost, target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"   // Esc
        createButton = ThemedButton(title: confirmTitle, style: .primary, target: self, action: #selector(createTapped))
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
        refreshConfirmEnabled()
    }

    /// Confirm is disabled while the (trimmed) field is blank — shared by the live edit callback
    /// and the initial seed in `present`, so a pre-filled rename shows an enabled confirm at once.
    private func refreshConfirmEnabled() {
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

// MARK: - DeleteFolderSheet

/// What to do with the prompts inside a folder being deleted.
enum FolderDeleteAction {
    case deleteAll
    case moveTo(String)   // "" = root/General
}

/// Themed sheet for deleting a non-empty folder — asks whether to move its prompts elsewhere
/// (default, safer) or delete them all. Same shape/chrome as `NewFolderSheet`/`ConfirmSheet`.
final class DeleteFolderSheet: NSObject {
    private var sheet: NSWindow!
    private var completion: ((FolderDeleteAction?) -> Void)?
    private var moveRadio: NSButton!
    private var deleteRadio: NSButton!
    private var destinationPopUp: ThemedPopUp!

    // Self-retain for the sheet's lifetime so the caller doesn't have to hold it.
    private static var active: DeleteFolderSheet?

    func present(over host: NSWindow, folderName: String, promptCount: Int, destinations: [String],
                 completion: @escaping (FolderDeleteAction?) -> Void) {
        self.completion = completion
        DeleteFolderSheet.active = self
        build(folderName: folderName, promptCount: promptCount, destinations: destinations)
        host.beginSheet(sheet, completionHandler: nil)
    }

    private func radioButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(radioButtonWithTitle: title, target: self, action: action)
        btn.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Palette.mono(12), .foregroundColor: Palette.primary,
        ])
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    private func build(folderName: String, promptCount: Int, destinations: [String]) {
        let pad: CGFloat = 20
        let width: CGFloat = 380
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 220),
                         styleMask: [.titled], backing: .buffered, defer: false)
        sheet.appearance = NSAppearance(named: .darkAqua)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 220))
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.surface2.cgColor
        sheet.contentView = content

        let header = NSTextField(labelWithString: "Delete folder \"\(folderName)\"?")
        header.font = Palette.monoMedium(14)
        header.textColor = Palette.primary
        header.backgroundColor = .clear
        header.isBordered = false
        header.lineBreakMode = .byTruncatingTail
        header.translatesAutoresizingMaskIntoConstraints = false

        let countText = promptCount == 1 ? "1 prompt is in this folder." : "\(promptCount) prompts are in this folder."
        let body = NSTextField(labelWithString: countText)
        body.font = Palette.mono(12)
        body.textColor = Palette.secondary
        body.backgroundColor = .clear
        body.isBordered = false
        body.translatesAutoresizingMaskIntoConstraints = false

        moveRadio = radioButton(title: "Move prompts to:", action: #selector(radioChanged))
        moveRadio.state = .on

        destinationPopUp = ThemedPopUp()
        for d in destinations { destinationPopUp.addItem(withTitle: d) }
        destinationPopUp.themeItems()

        deleteRadio = radioButton(title: "Delete all prompts permanently", action: #selector(radioChanged))

        let cancelButton = ThemedButton(title: "Cancel", style: .ghost, target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"   // Esc
        let confirmButton = ThemedButton(title: "Delete Folder", style: .destructive, target: self, action: #selector(confirmTapped))
        confirmButton.keyEquivalent = "\r"        // ↵ default

        [header, body, moveRadio, destinationPopUp, deleteRadio, cancelButton, confirmButton]
            .forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            moveRadio.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 16),
            moveRadio.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            destinationPopUp.centerYAnchor.constraint(equalTo: moveRadio.centerYAnchor),
            destinationPopUp.leadingAnchor.constraint(equalTo: moveRadio.trailingAnchor, constant: 8),
            destinationPopUp.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            destinationPopUp.heightAnchor.constraint(equalToConstant: 26),

            deleteRadio.topAnchor.constraint(equalTo: moveRadio.bottomAnchor, constant: 10),
            deleteRadio.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            confirmButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            confirmButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),
            cancelButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: confirmButton.centerYAnchor),
        ])
    }

    @objc private func radioChanged(_ sender: NSButton) {
        destinationPopUp.isEnabled = (sender == moveRadio)
    }

    @objc private func confirmTapped() {
        if deleteRadio.state == .on {
            finish(with: .deleteAll)
        } else {
            let dest = destinationPopUp.titleOfSelectedItem ?? "General"
            finish(with: .moveTo(dest == "General" ? "" : dest))
        }
    }
    @objc private func cancelTapped() { finish(with: nil) }

    private func finish(with result: FolderDeleteAction?) {
        if let host = sheet.sheetParent { host.endSheet(sheet) }
        completion?(result)
        completion = nil
        DeleteFolderSheet.active = nil
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
        content.layer?.backgroundColor = Palette.surface2.cgColor
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

// MARK: - ChipView (HUD hotkey chips, footer keycaps, Library hotkey badges)

/// A small rounded chip rendering a short mono string. One shared primitive for the palette's
/// per-row hotkey chip (a solid "permanent promise" plate), the keyboard-footer keycaps, and the
/// Library list's hotkey badges. Custom-drawn so it carries real internal padding (which a bare
/// NSTextField can't) — strict monochrome, no hue.
final class ChipView: NSView {
    enum Kind {
        case hud       // solid surface-3 plate, primary glyph — an explicit hotkey
        case keycap    // faint fill, hairline border, tertiary glyph — a keyboard-footer key
    }
    private let text: String
    private let kind: Kind
    private static let hPad: CGFloat = 6
    private static let chipHeight: CGFloat = 18

    init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var chipFont: NSFont { kind == .keycap ? Palette.footerKeyFont : Palette.hudNumeralFont }
    private var chipTextColor: NSColor { kind == .keycap ? Palette.textTertiary : Palette.textPrimary }

    override var intrinsicContentSize: NSSize {
        let w = NSAttributedString(string: text, attributes: [.font: chipFont]).size().width
        return NSSize(width: ceil(w) + Self.hPad * 2, height: Self.chipHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: Palette.Radius.chip, yRadius: Palette.Radius.chip)
        switch kind {
        case .hud:
            Palette.pinnedChipFill.setFill(); path.fill()
            NSColor(white: 1, alpha: 0.14).setStroke()
        case .keycap:
            Palette.keycapFill.setFill(); path.fill()
            Palette.hairline.setStroke()
        }
        path.lineWidth = 1
        path.stroke()
        let s = NSAttributedString(string: text, attributes: [.font: chipFont, .foregroundColor: chipTextColor])
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }
}
