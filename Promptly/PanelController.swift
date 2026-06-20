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
private let kPreviewMaxHeight: CGFloat = 220

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
/// Vertically centers text/placeholder within the tall filter field, instead of
/// the default top-aligned baseline.
final class VCenterTextFieldCell: NSTextFieldCell {
    private func centered(_ rect: NSRect) -> NSRect {
        let textSize = cellSize(forBounds: rect)
        let dy = (rect.height - textSize.height) / 2
        guard dy > 0 else { return rect }
        var r = rect
        r.origin.y += dy
        r.size.height -= dy
        return r
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centered(cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: centered(rect), in: controlView, editor: editor, delegate: delegate, start: start, length: length)
    }
}

final class FilterField: NSTextField {
    override class var cellClass: AnyClass? {
        get { VCenterTextFieldCell.self }
        set { }
    }

    var onEdit: (() -> Void)?
    /// ⌥1–9 — fire the prompt frozen at that HUD slot (Stage 7). Intercepted here, before the
    /// field editor would insert the option-modified character.
    var onHudSelect: ((Int) -> Void)?
    /// ⌘R — toggle history mode (Feature #4). Same interception reason as ⌘E.
    var onHistoryToggle: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "e" {
            onEdit?()
            return true
        }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "r" {
            onHistoryToggle?()
            return true
        }
        if event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let digit = Int(chars), (1...9).contains(digit) {
            onHudSelect?(digit)
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
    // Stage 7: trailing ⌥-number chip for the resting top-9 rows. Empty (zero-width) otherwise,
    // so a filtered row's title reclaims the full width.
    let slotLabel = NSTextField(labelWithString: "")
    init() {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Palette.mono(13)
        label.textColor = Palette.primary
        label.backgroundColor = .clear
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail
        slotLabel.translatesAutoresizingMaskIntoConstraints = false
        slotLabel.font = Palette.mono(11)
        slotLabel.textColor = Palette.footer
        slotLabel.backgroundColor = .clear
        slotLabel.isBordered = false
        slotLabel.alignment = .right
        slotLabel.setContentHuggingPriority(.required, for: .horizontal)
        slotLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)
        addSubview(slotLabel)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            slotLabel.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            slotLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            slotLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, query: String, trailing: String?) {
        slotLabel.stringValue = trailing ?? ""
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
    private var previewContainer: NSScrollView!
    private var previewTextView: NSTextView!
    private var previewFadeView: NSView!
    private var previewHeightConstraint: NSLayoutConstraint!

    private var results: [Prompt] = []
    private var selectedIndex = 0
    private var query: String { filterField?.stringValue ?? "" }
    private var committing = false
    // Stage 9: ⇥ toggles a read-only preview of the selected prompt's raw body. This tracks the
    // user's *intent* — it can stay true while there's transiently nothing to show (State C).
    private var previewOpen = false

    // Feature #4: ⌘R toggles a third palette mode showing usage history instead of the library.
    private var historyMode = false
    /// Parallel to `results`, same indices — only populated while `historyMode` is true.
    private var historyTimestamps: [Date] = []

    // Stage 4: in-place {{ask:label}} fill-in. Non-nil only while the panel is in ask mode —
    // the same surface, the field repurposed as the answer box, the panel frame FROZEN.
    private var askFlow: AskFlow?
    private var askPrompt: Prompt?
    private var isAsking: Bool { askFlow != nil }

    // Stage 7: ⌥1–9 slot → prompt, FROZEN at present-time and held until dismiss (no live
    // reshuffle — FEATURES §7). ⌥3 fires the same prompt for the whole appearance, even while
    // the filter changes the visible rows.
    private var hudAssignment: [Int: Prompt] = [:]

    private static let browseFooterBase = "↑/↓ move · ↵ paste · ⌫ delete · ⌘E edit · esc dismiss"
    private static let askFooter        = "↵ / ⇥ next · esc cancel"
    private static let historyFooter    = "↑/↓ move · ↵ paste · ⌘R search · esc back"

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
        filterField.onHudSelect = { [weak self] n in self?.hudSelect(n) }
        filterField.onHistoryToggle = { [weak self] in self?.toggleHistoryMode() }
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

        // Preview pane (⇥ toggle) — read-only raw body of the selected prompt, collapsed by
        // default (previewHeightConstraint starts at 0).
        previewTextView = NSTextView()
        previewTextView.minSize = NSSize(width: 0, height: 0)
        previewTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        previewTextView.isVerticallyResizable = true
        previewTextView.isHorizontallyResizable = false
        previewTextView.autoresizingMask = .width
        previewTextView.textContainer?.widthTracksTextView = true
        previewTextView.isEditable = false
        previewTextView.isSelectable = false
        previewTextView.backgroundColor = .clear
        previewTextView.font = Palette.mono(13)
        previewTextView.textColor = Palette.primary
        previewTextView.textContainerInset = NSSize(width: 16, height: 8)
        previewTextView.setAccessibilityLabel("Prompt preview")

        previewContainer = NSScrollView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.hasVerticalScroller = false
        previewContainer.drawsBackground = false
        previewContainer.backgroundColor = .clear
        previewContainer.documentView = previewTextView
        content.addSubview(previewContainer)

        previewFadeView = NSView()
        previewFadeView.translatesAutoresizingMaskIntoConstraints = false
        previewFadeView.wantsLayer = true
        let fadeLayer = CAGradientLayer()
        fadeLayer.colors = [NSColor.clear.cgColor, Palette.panelBG.cgColor]
        fadeLayer.locations = [0, 1]
        previewFadeView.layer = fadeLayer
        previewFadeView.isHidden = true
        content.addSubview(previewFadeView)

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
        previewHeightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            scrollHeightConstraint,
            previewHeightConstraint,

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

            previewContainer.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            previewFadeView.heightAnchor.constraint(equalToConstant: 20),
            previewFadeView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewFadeView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewFadeView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            footerLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor),
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
        previewOpen = false
        historyMode = false
        restoreBrowseChrome()
        filterField.stringValue = ""
        refreshResults()
        // Freeze the ⌥1–9 assignment for this appearance (Stage 7) — from the same ranked list
        // the resting (empty-query) rows show, so the chips match the keys.
        hudAssignment = HudRow.assign(pins: promptStore.pinnedAssignment(), ranked: promptStore.ranked())

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

    /// Opens the panel already in history mode — the menu-bar "Recent prompts…" entry point.
    func presentHistory(captured: CapturedApp) {
        present(captured: captured)
        enterHistoryMode()
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
        if historyMode {
            let pairs = promptStore.filterHistory(query)
            results = pairs.map { $0.0 }
            historyTimestamps = pairs.map { $0.1 }
        } else {
            results = promptStore.filter(query)
            historyTimestamps = []
        }
        selectedIndex = 0
        applyState()
        updatePreview()
    }

    private func applyState() {
        let libraryEmpty = promptStore.prompts.isEmpty

        if libraryEmpty {
            // State A0
            showEmpty("No prompts yet. Drop a .md file in ~/Prompts to begin →")
        } else if historyMode && results.isEmpty && query.isEmpty {
            showEmpty("No history yet — prompts you use will show here.")
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
        kFilterHeight + kSeparatorHeight + listHeight() + previewHeightConstraint.constant + kFooterHeight
    }

    // MARK: Preview pane (⇥ toggle)

    /// Re-renders the preview for the current selection and resizes the panel to match.
    /// `previewOpen` is the user's intent (set only by `togglePreview()` and the two explicit
    /// closes in `present`/`enterAskMode`); this also folds in whether there's currently
    /// anything to show, so a query with no matches collapses the pane without losing intent.
    private func updatePreview() {
        guard previewOpen, let prompt = selectedPrompt else {
            previewHeightConstraint.constant = 0
            previewFadeView.isHidden = true
            resizePanel()
            return
        }
        let attr = NSMutableAttributedString(
            string: prompt.body,
            attributes: [.font: Palette.mono(13), .foregroundColor: Palette.primary])
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let spanColor = increaseContrast ? Palette.primary : Palette.secondary
        for span in TokenEngine.spans(in: prompt.body) {
            attr.addAttribute(.foregroundColor, value: spanColor, range: NSRange(span.range, in: prompt.body))
        }
        previewTextView.textStorage?.setAttributedString(attr)

        previewTextView.layoutManager?.ensureLayout(for: previewTextView.textContainer!)
        let used = previewTextView.layoutManager?.usedRect(for: previewTextView.textContainer!) ?? .zero
        let contentHeight = ceil(used.height) + previewTextView.textContainerInset.height * 2
        let clamped = min(contentHeight, kPreviewMaxHeight)
        previewHeightConstraint.constant = clamped
        previewFadeView.isHidden = contentHeight <= kPreviewMaxHeight
        resizePanel()
    }

    private func togglePreview() {
        previewOpen.toggle()
        updatePreview()
        updateBrowseFooter()
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
        updatePreview()
    }

    private func commitSelected() {
        guard !committing else { return }
        guard !results.isEmpty, selectedIndex < results.count else {
            // State C: ↵ dismisses
            dismiss()
            return
        }
        commit(results[selectedIndex])
    }

    /// ⌥N — fire the prompt frozen at HUD slot N (Stage 7). Honors the freeze: works against the
    /// at-present-time assignment regardless of the current filter, and is inert during ask mode.
    private func hudSelect(_ n: Int) {
        guard !committing, !isAsking, !historyMode, let prompt = hudAssignment[n] else { return }
        commit(prompt)
    }

    /// Shared commit decision: a prompt with {{ask:…}} transforms the palette in place (Stage 4);
    /// otherwise it pastes (State D).
    private func commit(_ prompt: Prompt) {
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
        // The list area is repurposed for the ask progress line; the preview has no business
        // staying open underneath that. updatePreview() only resizes if the preview was actually
        // open (it collapses to 0 here) — the list/empty-label swap below never touches the frame.
        previewOpen = false
        updatePreview()
        // Repurpose the SAME surface: hide the list, keep the panel exactly where/what size it
        // is otherwise (spatial trust, FEATURES §7) — turn the field into the answer box, and use
        // the vacated list space for a quiet progress line.
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
        if historyMode { updateHistoryChrome() } else { restoreBrowseChrome() }
        filterField.stringValue = ""
        refreshResults()
    }

    private func restoreBrowseChrome() {
        filterField.placeholderAttributedString = NSAttributedString(
            string: "Search prompts…",
            attributes: [.font: Palette.mono(14), .foregroundColor: Palette.footer])
        updateBrowseFooter()
        footerLabel.isHidden = false
    }

    private func updateBrowseFooter() {
        footerLabel.stringValue = Self.browseFooterBase + (previewOpen ? " · ⇥ hide preview" : " · ⇥ preview")
    }

    // MARK: History mode (Feature #4) — ⌘R toggle

    private func toggleHistoryMode() {
        guard !isAsking else { return }   // can't switch palette mode mid fill-in
        if historyMode { exitHistoryMode() } else { enterHistoryMode() }
    }

    private func enterHistoryMode() {
        historyMode = true
        previewOpen = false
        filterField.stringValue = ""
        updateHistoryChrome()
        refreshResults()
    }

    private func exitHistoryMode() {
        historyMode = false
        previewOpen = false
        filterField.stringValue = ""
        restoreBrowseChrome()
        refreshResults()
    }

    private func updateHistoryChrome() {
        filterField.placeholderAttributedString = NSAttributedString(
            string: "Search history…",
            attributes: [.font: Palette.mono(14), .foregroundColor: Palette.footer])
        footerLabel.stringValue = Self.historyFooter
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
            if isAsking { cancelAsk() }
            else if previewOpen { togglePreview() }
            else if historyMode { exitHistoryMode() }
            else { dismiss() }
            return true
        case #selector(NSResponder.insertNewline(_:)):      // ↵
            if isAsking { askAdvance() } else { commitSelected() }
            return true
        case #selector(NSResponder.insertTab(_:)):          // ⇥ — advances an ask, else toggles preview
            if isAsking { askAdvance(); return true }
            if historyMode { return true }                  // preview is inert in history mode
            togglePreview()
            return true
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
        let trailing: String?
        if historyMode {
            trailing = RelativeTime.format(historyTimestamps[row], now: Date())
        } else if query.isEmpty && row < HudRow.slotCount {
            // Chips only in the resting (empty-query) state, where the visible rows are the
            // ranked list and so line up with the frozen ⌥1–9 assignment.
            trailing = "⌥\(row + 1)"
        } else {
            trailing = nil
        }
        cell.configure(name: prompt.name, query: query, trailing: trailing)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}

// MARK: - NSTextFieldDelegate conformance

extension PanelController: NSTextFieldDelegate {}
