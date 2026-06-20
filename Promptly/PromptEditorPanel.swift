import AppKit

// Editor window for creating and editing prompts.
// onSave is called with (name, keywords, body) on Save; the caller supplies filename.
final class PromptEditorPanel: NSWindow {
    var onSave: ((String, [String], String) -> Void)?

    private let nameField: NSTextField
    private let keywordsField: NSTextField
    private let bodyView: NSTextView

    // Colors shared with the rest of the Promptly dark palette
    private static let bg         = NSColor(red: 0x0f/255, green: 0x0f/255, blue: 0x14/255, alpha: 1)
    private static let primary    = NSColor(red: 0xe2/255, green: 0xe8/255, blue: 0xf0/255, alpha: 1)
    private static let secondary  = NSColor(red: 0x94/255, green: 0xa3/255, blue: 0xb8/255, alpha: 1)
    private static let border     = NSColor(white: 1.0, alpha: 0.12)
    private static func mono(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// `initialBody` pre-fills the body for a NEW prompt (Stage 5 inverse capture) while the
    /// title field takes focus — the one thing the author must supply.
    init(editing prompt: Prompt? = nil, initialBody: String? = nil) {
        // Initialize stored properties before super.init
        let nf = NSTextField()
        let kf = NSTextField()
        let tv = NSTextView()
        nameField = nf
        keywordsField = kf
        bodyView = tv

        let w: CGFloat = 560, h: CGFloat = 460
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)

        title = prompt == nil ? "New Prompt" : "Edit Prompt"
        minSize = NSSize(width: 400, height: 340)
        center()
        isReleasedWhenClosed = false
        backgroundColor = Self.bg

        buildContent(width: w, height: h)

        if let p = prompt {
            nameField.stringValue = p.name
            keywordsField.stringValue = p.keywords.joined(separator: " ")
            bodyView.string = p.body
        } else if let initialBody = initialBody {
            bodyView.string = initialBody
        }
        // Title field takes focus (the field the author must fill); the captured selection
        // already sits in the body.
        initialFirstResponder = nameField
    }

    private func buildContent(width w: CGFloat, height h: CGFloat) {
        let pad: CGFloat = 20
        let labelH: CGFloat = 18
        let fieldH: CGFloat = 28
        let btnH: CGFloat = 32
        let gap: CGFloat = 8

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        content.wantsLayer = true
        content.layer?.backgroundColor = Self.bg.cgColor
        contentView = content

        // Buttons (bottom strip)
        let cancelBtn = ghostButton(title: "Cancel")
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelPressed)

        let saveBtn = accentButton(title: "Save")
        saveBtn.target = self
        saveBtn.action = #selector(savePressed)

        let btnY: CGFloat = pad
        let saveW: CGFloat = 90
        let cancelW: CGFloat = 80
        saveBtn.frame = NSRect(x: w - pad - saveW, y: btnY, width: saveW, height: btnH)
        cancelBtn.frame = NSRect(x: w - pad - saveW - gap - cancelW, y: btnY, width: cancelW, height: btnH)
        content.addSubview(cancelBtn)
        content.addSubview(saveBtn)

        // Divider above buttons
        let divider = NSBox(frame: NSRect(x: 0, y: btnY + btnH + gap, width: w, height: 1))
        divider.boxType = .custom
        divider.borderWidth = 0
        divider.fillColor = Self.border
        content.addSubview(divider)

        let bodyTop = divider.frame.maxY
        let bottomReserved = bodyTop

        // Name field
        var cursor: CGFloat = h - pad

        let nameLabel = label("Name", y: cursor - labelH)
        cursor -= labelH + 4
        configureTextField(nameField, placeholder: "Prompt name", frame: NSRect(x: pad, y: cursor - fieldH, width: w - pad*2, height: fieldH))
        cursor -= fieldH + gap

        let kwLabel = label("Keywords  (space-separated)", y: cursor - labelH)
        cursor -= labelH + 4
        configureTextField(keywordsField, placeholder: "keyword1 keyword2", frame: NSRect(x: pad, y: cursor - fieldH, width: w - pad*2, height: fieldH))
        cursor -= fieldH + gap

        let bodyLabel = label("Body", y: cursor - labelH)
        cursor -= labelH + 4

        // Body scroll + text view
        let bodyH = cursor - bottomReserved - gap
        let scrollRect = NSRect(x: pad, y: bottomReserved, width: w - pad*2, height: max(bodyH, 80))
        let scroll = NSScrollView(frame: scrollRect)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 1.0, alpha: 0.05)
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 5
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = Self.border.cgColor

        let tvFrame = NSRect(x: 0, y: 0, width: scrollRect.width, height: scrollRect.height)
        bodyView.frame = tvFrame
        bodyView.minSize = NSSize(width: 0, height: scrollRect.height)
        bodyView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        bodyView.isVerticallyResizable = true
        bodyView.isHorizontallyResizable = false
        bodyView.autoresizingMask = .width
        bodyView.textContainer?.containerSize = NSSize(width: scrollRect.width, height: CGFloat.greatestFiniteMagnitude)
        bodyView.textContainer?.widthTracksTextView = true
        bodyView.backgroundColor = .clear
        bodyView.font = Self.mono(13)
        bodyView.textColor = Self.primary
        bodyView.insertionPointColor = Self.primary
        bodyView.isEditable = true
        bodyView.isSelectable = true
        scroll.documentView = bodyView

        content.addSubview(nameLabel)
        content.addSubview(nameField)
        content.addSubview(kwLabel)
        content.addSubview(keywordsField)
        content.addSubview(bodyLabel)
        content.addSubview(scroll)
    }

    private func label(_ text: String, y: CGFloat) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.frame = NSRect(x: 20, y: y, width: 400, height: 18)
        f.font = Self.mono(11)
        f.textColor = Self.secondary
        f.backgroundColor = .clear
        f.isBordered = false
        f.isEditable = false
        f.isSelectable = false
        return f
    }

    private func configureTextField(_ field: NSTextField, placeholder: String, frame: NSRect) {
        field.frame = frame
        field.font = Self.mono(13)
        field.textColor = Self.primary
        field.backgroundColor = NSColor(white: 1.0, alpha: 0.05)
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.layer?.borderWidth = 1
        field.layer?.borderColor = Self.border.cgColor
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: Self.mono(13), .foregroundColor: Self.secondary])
        field.cell?.wraps = false
        field.cell?.isScrollable = true
    }

    private func ghostButton(title: String) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.title = title
        btn.font = Self.mono(12)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 5
        btn.layer?.borderWidth = 1
        btn.layer?.borderColor = NSColor(white: 0.9, alpha: 0.2).cgColor
        btn.layer?.backgroundColor = NSColor.clear.cgColor
        btn.isBordered = false
        btn.contentTintColor = Self.secondary
        return btn
    }

    private func accentButton(title: String) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.title = title
        btn.font = Self.mono(12)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 5
        btn.layer?.backgroundColor = NSColor(white: 0.9, alpha: 0.15).cgColor
        btn.layer?.borderWidth = 1
        btn.layer?.borderColor = NSColor(white: 0.9, alpha: 0.35).cgColor
        btn.isBordered = false
        btn.contentTintColor = Self.primary
        return btn
    }

    @objc private func cancelPressed() { close() }

    @objc private func savePressed() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            let a = NSAlert()
            a.messageText = "Name required"
            a.informativeText = "Enter a name for this prompt."
            a.runModal()
            return
        }
        let rawKw = keywordsField.stringValue.trimmingCharacters(in: .whitespaces)
        let keywords = rawKw.isEmpty ? [] : rawKw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let body = bodyView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave?(name, keywords, body)
        close()
    }
}
