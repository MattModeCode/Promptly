import AppKit

private let kRowHeight: CGFloat = 38
private let kFilterHeight: CGFloat = 44
private let kFooterHeight: CGFloat = 28
private let kSeparatorHeight: CGFloat = 1
private let kMaxRows = 6
private let kPanelWidth: CGFloat = 560

// MARK: - Pinned-card strip layout

private let kPinnedLabelHeight: CGFloat = 18
private let kPinnedCardHeight: CGFloat = 52
private let kPinnedCardWidth: CGFloat = 150
private let kPinnedCardGap: CGFloat = 10
private let kPinnedSectionPadding: CGFloat = 16   // matches filterField's leading/trailing inset
private let kPinnedSectionTopGap: CGFloat = 12
private let kPinnedSectionBottomGap: CGFloat = 8

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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "e" {
            onEdit?()
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

// MARK: - Pinned card (hotkey badge + title; a glanceable shortcut strip, not the full list)

/// One card in the pinned strip. Shows the prompt's hotkey badge (blank if it has none — pinned
/// and hotkey are independent) and title. Participates in the same ↑/↓ traversal as the regular
/// list, so it carries its own selection highlight mirroring `PromptRowView`'s bar/fill treatment.
private final class PinnedCardView: NSView {
    private let hotkeyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    var isSelected: Bool = false {
        didSet {
            layer?.backgroundColor = isSelected ? Palette.selFill.cgColor : NSColor.clear.cgColor
            layer?.borderColor = (isSelected ? Palette.selBar : Palette.separator).cgColor
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = Palette.separator.cgColor

        hotkeyLabel.translatesAutoresizingMaskIntoConstraints = false
        hotkeyLabel.font = Palette.mono(11)
        hotkeyLabel.textColor = Palette.footer
        hotkeyLabel.backgroundColor = .clear
        hotkeyLabel.isBordered = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Palette.mono(12)
        titleLabel.textColor = Palette.primary
        titleLabel.backgroundColor = .clear
        titleLabel.isBordered = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true
        // `labelWithString` defaults to single-line mode, which silently overrides
        // `maximumNumberOfLines` — found by visual self-verification (the title rendered as one
        // truncated line instead of wrapping to two).
        titleLabel.usesSingleLineMode = false

        addSubview(hotkeyLabel)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            hotkeyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            hotkeyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            hotkeyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            titleLabel.topAnchor.constraint(equalTo: hotkeyLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, hotkey: Int?) {
        hotkeyLabel.stringValue = hotkey.map { "⌥\($0)" } ?? ""
        titleLabel.stringValue = title
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
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

    func configure(name: String, query: String, slot: Int?) {
        slotLabel.stringValue = slot.map { "⌥\($0)" } ?? ""
        // One consistent chip style — a hotkey is purely explicit now, no frecency-filled
        // chip to distinguish it from.
        slotLabel.font = Palette.mono(11)
        slotLabel.textColor = Palette.footer
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

    /// `selectedIndex` ranges over the COMBINED sequence: pinned cards first, then the regular
    /// list — one continuous ↑/↓ traversal, per the confirmed design. A pinned+hotkeyed prompt
    /// can legitimately appear twice (once as a card, once in its normal list position).
    var selectedPrompt: Prompt? {
        let total = pinnedResults.count + results.count
        guard total > 0, selectedIndex < total else { return nil }
        return selectedIndex < pinnedResults.count
            ? pinnedResults[selectedIndex]
            : results[selectedIndex - pinnedResults.count]
    }

    private var panel: NSPanel!
    private var filterField: FilterField!
    private var separator: NSBox!
    private var pinnedContainer: NSView!
    private var pinnedLabel: NSTextField!
    private var pinnedContainerHeightConstraint: NSLayoutConstraint!
    private var pinnedCardViews: [PinnedCardView] = []
    private var scrollView: NSScrollView!
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!
    private var footerLabel: NSTextField!

    private var results: [Prompt] = []
    /// Pinned prompts matching the current filter — a glanceable strip on top of the full
    /// searchable list below. Recomputed live every keystroke (unlike `hudAssignment`, which
    /// stays frozen for the appearance); pinned status is purely organizational, not part of
    /// the no-live-reshuffle hotkey-firing contract.
    private var pinnedResults: [Prompt] = []
    private var selectedIndex = 0
    private var query: String { filterField?.stringValue ?? "" }
    private var committing = false
    /// Set while `applySelectionHighlighting()` programmatically drives `tableView`'s selection,
    /// so `tableViewSelectionDidChange` can tell that apart from a real mouse click and not loop
    /// back into `selectedIndex`.
    private var syncingTableSelection = false

    // Stage 4: in-place {{ask:label}} fill-in. Non-nil only while the panel is in ask mode —
    // the same surface, the field repurposed as the answer box, the panel frame FROZEN.
    private var askFlow: AskFlow?
    private var askPrompt: Prompt?
    private var isAsking: Bool { askFlow != nil }

    // Stage 7: ⌥1–9 slot → prompt, FROZEN at present-time and held until dismiss (no live
    // reshuffle — FEATURES §7). ⌥3 fires the same prompt for the whole appearance, even while
    // the filter changes the visible rows.
    private var hudAssignment: [Int: Prompt] = [:]
    // Frozen alongside `hudAssignment` (same appearance, same freeze invariant) — filename →
    // hotkey, for the row chip lookup. Never recomputed live from the store (which could diverge
    // mid-appearance if hotkeys change on disk via the Library window).
    private var hudSlotByFilename: [String: Int] = [:]

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
        filterField.onHudSelect = { [weak self] n in self?.hudSelect(n) }
        content.addSubview(filterField)

        // Separator
        separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.fillColor = Palette.separator
        content.addSubview(separator)

        // Pinned-card strip — collapses to zero height when there are no pinned matches
        // (see `rebuildPinnedCards()`). Its own children are laid out with manual frames
        // (a flow-wrap grid), while the container itself is Auto-Layout-pinned in the stack.
        pinnedContainer = NSView()
        pinnedContainer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pinnedContainer)

        pinnedLabel = NSTextField(labelWithString: "pinned")
        pinnedLabel.font = Palette.mono(11)
        pinnedLabel.textColor = Palette.footer
        pinnedLabel.backgroundColor = .clear
        pinnedLabel.isBordered = false
        pinnedLabel.frame = NSRect(x: kPinnedSectionPadding, y: 0, width: 100, height: kPinnedLabelHeight)
        pinnedContainer.addSubview(pinnedLabel)

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
        // Zero by default (no pins yet); `rebuildPinnedCards()` grows it to fit.
        pinnedContainerHeightConstraint = pinnedContainer.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            scrollHeightConstraint,
            pinnedContainerHeightConstraint,

            filterField.topAnchor.constraint(equalTo: content.topAnchor),
            filterField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            filterField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            filterField.heightAnchor.constraint(equalToConstant: kFilterHeight),

            separator.topAnchor.constraint(equalTo: filterField.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: kSeparatorHeight),

            pinnedContainer.topAnchor.constraint(equalTo: separator.bottomAnchor),
            pinnedContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pinnedContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: pinnedContainer.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            footerLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footerLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footerLabel.heightAnchor.constraint(equalToConstant: kFooterHeight),

            emptyLabel.topAnchor.constraint(equalTo: pinnedContainer.bottomAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            emptyLabel.bottomAnchor.constraint(equalTo: footerLabel.topAnchor),
        ])
    }

    // MARK: Present / dismiss

    /// Whether the panel is currently on screen — lets the global hotkey toggle (press again to
    /// close) instead of unconditionally re-presenting.
    var isPresented: Bool { panel.isVisible }

    func present(captured: CapturedApp) {
        lastCaptured = captured
        committing = false
        askFlow = nil
        askPrompt = nil
        restoreBrowseChrome()
        filterField.stringValue = ""
        refreshResults()
        // Freeze the ⌥1–9 assignment for this appearance — a hotkey is purely an explicit
        // per-prompt attribute now (no frecency autofill), so this is just the resolved
        // hotkey→prompt map, frozen so a Library-window edit mid-appearance can't retarget
        // what a number fires until the next open.
        hudAssignment = promptStore.hotkeyAssignment()
        hudSlotByFilename = Dictionary(
            uniqueKeysWithValues: hudAssignment.map { ($0.value.filename, $0.key) })

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
        let filtered = promptStore.filter(query)
        results = filtered
        pinnedResults = filtered.filter { $0.pinned }
        selectedIndex = 0
        rebuildPinnedCards()
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
            pinnedContainer.isHidden = false
            tableView.reloadData()
            applySelectionHighlighting()
        }
        scrollHeightConstraint.constant = listHeight()
        resizePanel()
    }

    private func showEmpty(_ text: String) {
        emptyLabel.stringValue = text
        emptyLabel.isHidden = false
        scrollView.isHidden = true
    }

    /// Rebuilds the pinned-card views from `pinnedResults` (flow-wrapped grid, manual frames —
    /// `pinnedContainer` itself stays Auto-Layout-pinned; only its children are laid out by
    /// hand) and grows/collapses `pinnedContainerHeightConstraint` to fit, mirroring how
    /// `scrollHeightConstraint` is driven for the regular list. `pinnedContainer` is a plain
    /// (non-flipped) `NSView`, so y=0 is its bottom edge and y increases upward.
    private func rebuildPinnedCards() {
        pinnedCardViews.forEach { $0.removeFromSuperview() }
        pinnedCardViews = []

        guard !pinnedResults.isEmpty else {
            pinnedLabel.isHidden = true
            pinnedContainerHeightConstraint.constant = 0
            return
        }
        pinnedLabel.isHidden = false

        let availableWidth = kPanelWidth - 2 * kPinnedSectionPadding
        let perRow = max(1, Int((availableWidth + kPinnedCardGap) / (kPinnedCardWidth + kPinnedCardGap)))
        let rows = (pinnedResults.count + perRow - 1) / perRow
        let containerHeight = pinnedContainerHeightFor(rows: rows)
        pinnedContainerHeightConstraint.constant = containerHeight

        // Top-down: the label sits just below the separator; row 0 of cards sits flush under
        // the label; later rows stack downward toward the container's bottom edge.
        let labelTop = containerHeight - kPinnedSectionTopGap
        pinnedLabel.frame.origin.y = labelTop - kPinnedLabelHeight
        let cardsTop = labelTop - kPinnedLabelHeight

        for (i, prompt) in pinnedResults.enumerated() {
            let row = i / perRow
            let col = i % perRow
            let x = kPinnedSectionPadding + CGFloat(col) * (kPinnedCardWidth + kPinnedCardGap)
            let y = cardsTop - CGFloat(row + 1) * kPinnedCardHeight - CGFloat(row) * kPinnedCardGap
            let card = PinnedCardView(frame: NSRect(x: x, y: y, width: kPinnedCardWidth, height: kPinnedCardHeight))
            card.configure(title: prompt.name, hotkey: hudSlotByFilename[prompt.filename])
            let index = i
            card.onClick = { [weak self] in self?.selectCard(at: index) }
            pinnedContainer.addSubview(card)
            pinnedCardViews.append(card)
        }
    }

    private func pinnedContainerHeightFor(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return kPinnedSectionTopGap + kPinnedLabelHeight
            + CGFloat(rows) * kPinnedCardHeight + CGFloat(rows - 1) * kPinnedCardGap
            + kPinnedSectionBottomGap
    }

    private func selectCard(at index: Int) {
        guard !committing else { return }
        selectedIndex = index
        applySelectionHighlighting()
    }

    /// Applies the combined-index selection to whichever surface it falls in — a pinned card
    /// or a regular row — and clears highlighting on the other. Safe to call with either array
    /// empty (no-ops).
    private func applySelectionHighlighting() {
        syncingTableSelection = true
        defer { syncingTableSelection = false }
        if selectedIndex < pinnedResults.count {
            tableView.deselectAll(nil)
            for (i, card) in pinnedCardViews.enumerated() { card.isSelected = (i == selectedIndex) }
        } else {
            for card in pinnedCardViews { card.isSelected = false }
            let row = selectedIndex - pinnedResults.count
            guard row < results.count else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
    }

    /// Height of the list/empty-message area between the pinned strip and footer.
    private func listHeight() -> CGFloat {
        if promptStore.prompts.isEmpty || results.isEmpty {
            return kRowHeight   // one line for the empty/no-match message
        }
        return CGFloat(min(results.count, kMaxRows)) * kRowHeight
    }

    private func panelHeight() -> CGFloat {
        kFilterHeight + kSeparatorHeight + pinnedContainerHeightConstraint.constant + listHeight() + kFooterHeight
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
        let total = pinnedResults.count + results.count
        guard total > 0 else { return }
        selectedIndex = max(0, min(total - 1, selectedIndex + delta))
        applySelectionHighlighting()
    }

    private func commitSelected() {
        guard !committing else { return }
        guard let prompt = selectedPrompt else {
            // State C: ↵ dismisses
            dismiss()
            return
        }
        commit(prompt)
    }

    /// ⌥N — fire the prompt frozen at HUD slot N (Stage 7). Honors the freeze: works against the
    /// at-present-time assignment regardless of the current filter, and is inert during ask mode.
    private func hudSelect(_ n: Int) {
        guard !committing, !isAsking, let prompt = hudAssignment[n] else { return }
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
        // Repurpose the SAME surface: hide the list AND the pinned strip, keep the panel
        // exactly where/what size it is (do NOT call resizePanel — spatial trust, FEATURES §7),
        // turn the field into the answer box, and use the vacated space for a quiet progress line.
        scrollView.isHidden = true
        pinnedContainer.isHidden = true
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
        // (Pinned cards are already layer-backed and redraw instantly on `isSelected`, so only
        // the table-row case needs an explicit redraw nudge here.)
        if selectedIndex >= pinnedResults.count {
            let row = selectedIndex - pinnedResults.count
            if row < results.count {
                tableView.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
            }
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
        // The chip shows whenever this exact prompt has an explicit hotkey — from the FROZEN
        // hudAssignment, not live, so it can't retarget mid-appearance; independent of the
        // current filter text (a hotkey is a fixed fact about the prompt, not a ranking guess).
        let slot = hudSlotByFilename[prompt.filename]
        cell.configure(name: prompt.name, query: query, slot: slot)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    /// A real mouse click on a row only changes the table's own selection model — without this,
    /// `selectedIndex` (the arrow-key state Enter actually fires) stays stale, so a click visibly
    /// highlights one row while ↵ commits another. Mirrors `selectCard(at:)`'s sync for pinned
    /// cards, which already routes clicks through `selectedIndex`.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingTableSelection, !committing else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        for card in pinnedCardViews { card.isSelected = false }
        selectedIndex = pinnedResults.count + row
    }
}

// MARK: - NSTextFieldDelegate conformance

extension PanelController: NSTextFieldDelegate {}
