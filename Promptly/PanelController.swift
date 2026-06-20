import AppKit

// MARK: - Mattmode Mono palette

private enum Palette {
    static let panelBG     = NSColor(red: 0x0f/255, green: 0x0f/255, blue: 0x14/255, alpha: 1)
    static let primary     = NSColor(red: 0xe2/255, green: 0xe8/255, blue: 0xf0/255, alpha: 1)
    static let secondary   = NSColor(red: 0x94/255, green: 0xa3/255, blue: 0xb8/255, alpha: 1)
    static let footer      = NSColor(red: 0x64/255, green: 0x74/255, blue: 0x8b/255, alpha: 1)
    static let matched     = NSColor.white
    static let selFill     = NSColor(white: 0.9, alpha: 0.10)
    static let selBar      = NSColor(white: 0.9, alpha: 0.55)
    static let separator   = NSColor(white: 1.0, alpha: 0.15)

    static func mono(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    static func monoMedium(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Medium", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }
}

private let kRowHeight: CGFloat = 38
private let kFilterHeight: CGFloat = 44
private let kFooterHeight: CGFloat = 28
private let kSeparatorHeight: CGFloat = 1
private let kMaxRows = 6
private let kPanelWidth: CGFloat = 560

// MARK: - Key-capable panel

/// A borderless `NSWindow`/`NSPanel` cannot become key by default, which would
/// leave the search field unable to receive keystrokes. Override so the
/// nonactivating panel can take key focus (it never becomes *main*, preserving
/// the never-steal-focus behavior).
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Filter field

/// `⌘E` (edit selected) isn't a field-editor command selector, so it can't be
/// caught via `doCommandBy:` like Esc/Return/arrows. Intercept it here at the
/// key-equivalent layer; everything else is handled by the delegate.
final class FilterField: NSTextField {
    var onEdit: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "e" {
            onEdit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Selected row drawing

final class PromptRowView: NSTableRowView {
    override var isSelected: Bool { didSet { setNeedsDisplay(bounds) } }
    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            Palette.selFill.setFill()
            bounds.fill()
            let bar = NSRect(x: 0, y: 0, width: 2, height: bounds.height)
            Palette.selBar.setFill()
            bar.fill()
        }
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

// MARK: - Row cell (name + matched-char highlighting)

private final class PromptCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    init() {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Palette.mono(13)
        label.textColor = Palette.primary
        label.backgroundColor = .clear
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, query: String) {
        if query.isEmpty {
            label.attributedStringValue = NSAttributedString(
                string: name,
                attributes: [.font: Palette.mono(13), .foregroundColor: Palette.primary])
            return
        }
        label.attributedStringValue = highlight(name, query: query)
    }

    private func highlight(_ name: String, query: String) -> NSAttributedString {
        let attr = NSMutableAttributedString(
            string: name,
            attributes: [.font: Palette.mono(13), .foregroundColor: Palette.primary])
        let lowerName = Array(name.lowercased())
        let lowerQuery = Array(query.lowercased())
        var qi = 0
        for (i, ch) in lowerName.enumerated() {
            if qi < lowerQuery.count && ch == lowerQuery[qi] {
                attr.addAttributes([.font: Palette.monoMedium(13),
                                    .foregroundColor: Palette.matched],
                                   range: NSRange(location: i, length: 1))
                qi += 1
            }
        }
        return attr
    }
}

// MARK: - Panel controller

final class PanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    var promptStore: PromptStore!
    /// (selected prompt, body to paste). The body equals `prompt.body` for a plain prompt and
    /// the ask-filled body once a `{{ask:…}}` flow completes; static tokens are expanded downstream.
    var onCommit: ((Prompt, String) -> Void)?
    var onDismiss: (() -> Void)?
    var onDelete: ((Prompt) -> Void)?
    var onEdit: ((Prompt) -> Void)?
    private(set) var lastCaptured: CapturedApp?

    var selectedPrompt: Prompt? {
        guard !results.isEmpty, selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    private var panel: NSPanel!
    private var filterField: FilterField!
    private var separator: NSBox!
    private var scrollView: NSScrollView!
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!
    private var footerLabel: NSTextField!

    private var results: [Prompt] = []
    private var selectedIndex = 0
    private var query: String { filterField?.stringValue ?? "" }
    private var committing = false

    // Stage 4: in-place {{ask:label}} fill-in. Non-nil only while the panel is in ask mode —
    // the same surface, the field repurposed as the answer box, the panel frame FROZEN.
    private var askFlow: AskFlow?
    private var askPrompt: Prompt?
    private var isAsking: Bool { askFlow != nil }

    private static let browseFooter = "↑/↓ move · ↵ paste · ⌫ delete · ⌘E edit · esc dismiss"
    private static let askFooter    = "↵ / ⇥ next · esc cancel"

    override init() {
        super.init()
        buildPanel()
    }

    // MARK: Build

    private func buildPanel() {
        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: kPanelWidth, height: 300),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: kPanelWidth, height: 300))
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.panelBG.cgColor
        content.layer?.cornerRadius = 10
        content.layer?.masksToBounds = true
        panel.contentView = content
        // A manually-assigned contentView on a borderless panel must explicitly
        // track the window frame, or Auto Layout collapses the flexible scroll
        // view (the cramped-panel bug).
        content.autoresizingMask = [.width, .height]

        // Filter field
        filterField = FilterField(frame: .zero)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.font = Palette.mono(14)
        filterField.textColor = Palette.primary
        filterField.backgroundColor = Palette.panelBG
        filterField.drawsBackground = true
        filterField.isBordered = false
        filterField.focusRingType = .none
        filterField.placeholderAttributedString = NSAttributedString(
            string: "Search prompts…",
            attributes: [.font: Palette.mono(14), .foregroundColor: Palette.footer])
        filterField.delegate = self
        filterField.onEdit = { [weak self] in
            guard let self, let p = selectedPrompt else { return }
            onEdit?(p)
        }
        content.addSubview(filterField)

        // Separator
        separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.fillColor = Palette.separator
        content.addSubview(separator)

        // Table
        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.rowHeight = kRowHeight
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.refusesFirstResponder = true
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        content.addSubview(scrollView)

        // Empty-state label (state A0 / C)
        emptyLabel = NSTextField(labelWithString: "")
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = Palette.mono(13)
        emptyLabel.textColor = Palette.footer
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        content.addSubview(emptyLabel)

        // Footer
        footerLabel = NSTextField(labelWithString: "↑/↓ move · ↵ paste · ⌫ delete · ⌘E edit · esc dismiss")
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = Palette.mono(11)
        footerLabel.textColor = Palette.footer
        footerLabel.alignment = .center
        footerLabel.backgroundColor = .clear
        footerLabel.isBordered = false
        content.addSubview(footerLabel)

        // Pin the list height explicitly so Auto Layout can never squeeze it to
        // zero. Updated per state in `applyState()`.
        scrollHeightConstraint = scrollView.heightAnchor.constraint(
            equalToConstant: CGFloat(kMaxRows) * kRowHeight)

        NSLayoutConstraint.activate([
            scrollHeightConstraint,

            filterField.topAnchor.constraint(equalTo: content.topAnchor),
            filterField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            filterField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            filterField.heightAnchor.constraint(equalToConstant: kFilterHeight),

            separator.topAnchor.constraint(equalTo: filterField.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: kSeparatorHeight),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            footerLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footerLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footerLabel.heightAnchor.constraint(equalToConstant: kFooterHeight),

            emptyLabel.topAnchor.constraint(equalTo: separator.bottomAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            emptyLabel.bottomAnchor.constraint(equalTo: footerLabel.topAnchor),
        ])
    }

    // MARK: Present / dismiss

    func present(captured: CapturedApp) {
        lastCaptured = captured
        committing = false
        askFlow = nil
        askPrompt = nil
        restoreBrowseChrome()
        filterField.stringValue = ""
        refreshResults()

        let screen = captured.screen
        let h = panelHeight()
        let x = screen.frame.midX - kPanelWidth / 2
        let y = screen.frame.minY + screen.frame.height * 0.70
        panel.setFrame(NSRect(x: x, y: y, width: kPanelWidth, height: h), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(filterField)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.09
            panel.animator().alphaValue = 1
        }
    }

    func dismiss() {
        panel.orderOut(nil)
        onDismiss?()
    }

    func dismissAfterSuccessfulPaste() {
        commitAnimation { [weak self] in self?.dismiss() }
    }

    func showFailure(message: String) {
        emptyLabel.stringValue = message
        emptyLabel.isHidden = false
        scrollView.isHidden = true
        // Auto-dismiss after a beat so the failure note is seen but not sticky.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.dismiss()
        }
    }

    // MARK: Results / state

    private func refreshResults() {
        results = promptStore.filter(query)
        selectedIndex = 0
        applyState()
    }

    private func applyState() {
        let libraryEmpty = promptStore.prompts.isEmpty

        if libraryEmpty {
            // State A0
            showEmpty("No prompts yet. Drop a .md file in ~/Prompts to begin →")
        } else if results.isEmpty {
            // State C
            showEmpty("No match · ↵ to dismiss")
        } else {
            // State A (recents) or B (filtering)
            emptyLabel.isHidden = true
            scrollView.isHidden = false
            tableView.reloadData()
            if selectedIndex < results.count {
                tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
                tableView.scrollRowToVisible(selectedIndex)
            }
        }
        scrollHeightConstraint.constant = listHeight()
        resizePanel()
    }

    private func showEmpty(_ text: String) {
        emptyLabel.stringValue = text
        emptyLabel.isHidden = false
        scrollView.isHidden = true
    }

    /// Height of the list/empty-message area between the separator and footer.
    private func listHeight() -> CGFloat {
        if promptStore.prompts.isEmpty || results.isEmpty {
            return kRowHeight   // one line for the empty/no-match message
        }
        return CGFloat(min(results.count, kMaxRows)) * kRowHeight
    }

    private func panelHeight() -> CGFloat {
        kFilterHeight + kSeparatorHeight + listHeight() + kFooterHeight
    }

    private func resizePanel() {
        let h = panelHeight()
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = h
        frame.origin.y = top - h   // keep the top edge anchored
        panel.setFrame(frame, display: true)
    }

    // MARK: Selection

    private func confirmDeleteSelected() {
        guard let prompt = selectedPrompt else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \"\(prompt.name)\"?"
        alert.informativeText = "Removes the file from ~/Prompts. Cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            onDelete?(prompt)
            promptStore.delete(prompt)
            refreshResults()
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    private func commitSelected() {
        guard !committing else { return }
        guard !results.isEmpty, selectedIndex < results.count else {
            // State C: ↵ dismisses
            dismiss()
            return
        }
        let prompt = results[selectedIndex]
        // Stage 4: a prompt with {{ask:…}} transforms the palette in place instead of pasting.
        if let flow = AskFlow(body: prompt.body) {
            enterAskMode(prompt: prompt, flow: flow)
            return
        }
        fire(prompt: prompt, body: prompt.body)
    }

    /// Commit the assembled body to the host app (State D). Drops the footer immediately; the
    /// paste itself is driven by onCommit → dismissAfterSuccessfulPaste / showFailure.
    private func fire(prompt: Prompt, body: String) {
        committing = true
        footerLabel.isHidden = true
        onCommit?(prompt, body)
    }

    // MARK: Ask mode (Stage 4) — in-place fill-in; panel frame stays frozen

    private func enterAskMode(prompt: Prompt, flow: AskFlow) {
        askPrompt = prompt
        askFlow = flow
        // Repurpose the SAME surface: hide the list, keep the panel exactly where/what size it
        // is (do NOT call resizePanel — spatial trust, FEATURES §7), turn the field into the
        // answer box, and use the vacated list space for a quiet progress line.
        scrollView.isHidden = true
        emptyLabel.isHidden = false
        filterField.stringValue = ""
        updateAskChrome()
    }

    private func updateAskChrome() {
        guard let flow = askFlow else { return }
        let p = flow.progress
        filterField.placeholderAttributedString = NSAttributedString(
            string: "\(flow.currentLabel) ›",
            attributes: [.font: Palette.mono(14), .foregroundColor: Palette.footer])
        emptyLabel.stringValue = "\(p.current) of \(p.total)"
        footerLabel.stringValue = Self.askFooter
    }

    /// ↵ or ⇥: record the current answer, advance, and either prompt for the next ask or
    /// assemble the final body and fire the paste.
    private func askAdvance() {
        guard var flow = askFlow, let prompt = askPrompt else { return }
        let more = flow.advance(with: filterField.stringValue)
        askFlow = flow
        if more {
            filterField.stringValue = ""
            updateAskChrome()
        } else {
            let body = flow.finalText(body: prompt.body)
            askFlow = nil
            askPrompt = nil
            fire(prompt: prompt, body: body)
        }
    }

    /// esc cancels the WHOLE expansion (FEATURES §7) and returns to the browse palette; a
    /// second esc then dismisses as usual.
    private func cancelAsk() {
        askFlow = nil
        askPrompt = nil
        restoreBrowseChrome()
        filterField.stringValue = ""
        refreshResults()
    }

    private func restoreBrowseChrome() {
        filterField.placeholderAttributedString = NSAttributedString(
            string: "Search prompts…",
            attributes: [.font: Palette.mono(14), .foregroundColor: Palette.footer])
        footerLabel.stringValue = Self.browseFooter
        footerLabel.isHidden = false
    }

    // MARK: State D animation

    private func commitAnimation(then: @escaping () -> Void) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            then()
            return
        }
        // ~80ms pulse on the selected row (re-draw at full selection), then ~120ms fade.
        if selectedIndex < results.count {
            tableView.rowView(atRow: selectedIndex, makeIfNecessary: false)?.needsDisplay = true
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                self.panel.alphaValue = 1
                then()
            })
        })
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        // In ask mode the field is an answer box, not a filter — don't re-query the store.
        guard !isAsking else { return }
        refreshResults()
    }

    /// While the search field is being edited the field editor (a shared
    /// `NSTextView`) is first responder and consumes Esc/Return/arrows/⌫ before
    /// they reach the field's `keyDown` — so they must be intercepted here.
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):   // esc
            if isAsking { cancelAsk() } else { dismiss() }
            return true
        case #selector(NSResponder.insertNewline(_:)):      // ↵
            if isAsking { askAdvance() } else { commitSelected() }
            return true
        case #selector(NSResponder.insertTab(_:)):          // ⇥ — advances an ask
            if isAsking { askAdvance(); return true }
            return false
        case #selector(NSResponder.moveUp(_:)):             // ↑
            if isAsking { return true }                     // no list in ask mode — swallow
            moveSelection(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):           // ↓
            if isAsking { return true }
            moveSelection(1)
            return true
        case #selector(NSResponder.deleteBackward(_:)):     // ⌫ — delete selected when empty
            if !isAsking, textView.string.isEmpty {
                confirmDeleteSelected()
                return true
            }
            return false                                    // in ask mode: normal text delete
        default:
            return false
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PromptRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("PromptCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PromptCellView) ?? {
            let c = PromptCellView()
            c.identifier = id
            return c
        }()
        let prompt = results[row]
        cell.configure(name: prompt.name, query: query)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}

// MARK: - NSTextFieldDelegate conformance

extension PanelController: NSTextFieldDelegate {}
