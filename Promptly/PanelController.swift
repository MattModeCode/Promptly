import AppKit
import QuartzCore

private let kRowHeight: CGFloat = 38
private let kFilterHeight: CGFloat = 44
private let kFooterHeight: CGFloat = 28
private let kSeparatorHeight: CGFloat = 1
private let kCaptionHeight: CGFloat = 20
private let kMaxRows = 6
private let kPanelWidth: CGFloat = 560
private let kPreviewMaxHeight: CGFloat = 220   // preview clamps here; taller bodies scroll (Part A)

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
    /// ⌘1–9 — fire the prompt frozen at that HUD slot (Stage 7). Intercepted here, before the
    /// field editor would insert the character. (Was ⌥1–9; Option+digit collides with macOS's
    /// reserved special-character combo, so this moved to Command+digit.)
    var onHudSelect: ((Int) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.option),
           event.charactersIgnoringModifiers?.lowercased() == "e" {
            onEdit?()
            return true
        }
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.option),
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
    override var isSelected: Bool {
        didSet {
            setNeedsDisplay(bounds)
            // Lift the cell's title secondary→primary in lockstep (a core Lightfall cue).
            //
            // `view(atColumn:)` raises NSRangeException when the row has no column views yet.
            // AppKit sets `isSelected` during *static* row configuration
            // (_setPropertiesForRowView:atRow:isStatic:) BEFORE it installs the column views — a path
            // hit when the palette relayouts (resizePanel → setFrame) while Promptly is the active
            // app, e.g. right after the "Rebind Hotkey…" window activated it. Unguarded, that threw
            // an unhandled ObjC exception and crashed the app the instant the palette opened, which
            // read as "the rebound hotkey crashes it" but was independent of the combo. Guard on
            // column count: with no columns there is nothing to restyle yet — the real selection
            // highlight is applied post-reload by applySelectionHighlighting(), when columns exist.
            guard numberOfColumns > 0 else { return }
            (view(atColumn: 0) as? PromptCellView)?.setSelected(isSelected)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        // Lightfall: four stacked, colour-independent cues so "what ↵ fires" reads pre-consciously.
        // (1) faint fill plate.
        Palette.selectedFill.setFill()
        bounds.fill()
        let railW: CGFloat = 3
        // (2) rightward glow — drawn INSIDE bounds as a gradient (the content view masksToBounds, so a
        // CALayer shadow would be clipped flat; this is the blueprint's explicit requirement).
        if let glow = NSGradient(starting: Palette.selectedRailGlow, ending: .clear) {
            glow.draw(in: NSRect(x: railW, y: 0, width: 8, height: bounds.height), angle: 0)
        }
        // (3) the 3px rail — the primary peripheral signal.
        Palette.selectedRail.setFill()
        NSRect(x: 0, y: 0, width: railW, height: bounds.height).fill()
        // (4) 1px lit top bevel (reads as raised). Row views are flipped, so the top edge is y=0.
        let topY: CGFloat = isFlipped ? 0 : bounds.height - 1
        Palette.selectedBevel.setFill()
        NSRect(x: 0, y: topY, width: bounds.width, height: 1).fill()
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
        hotkeyLabel.stringValue = hotkey.map { "⌘\($0)" } ?? ""
        titleLabel.stringValue = title
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

// MARK: - Row cell (name + matched-char highlighting)

private final class PromptCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    /// Trailing ⌘-number chip for a prompt with an explicit hotkey — a solid "permanent promise"
    /// plate (ChipView). Absent (label reclaims the width) when the prompt has no hotkey.
    private var chip: ChipView?
    /// Trailing relative-time label, shown only in history mode. Mutually exclusive with `chip`.
    private var timeView: NSTextField?
    private var labelTrailing: NSLayoutConstraint!
    private var currentName = ""
    private var currentQuery = ""
    private var selected = false

    init() {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Palette.rowTitleFont
        label.textColor = Palette.textSecondary
        label.backgroundColor = .clear
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        labelTrailing = label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),  // 3px rail lane + air
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelTrailing,
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, query: String, slot: Int?, time: String?) {
        currentName = name
        currentQuery = query
        selected = false
        chip?.removeFromSuperview()
        chip = nil
        timeView?.removeFromSuperview()
        timeView = nil
        labelTrailing.isActive = true
        if let time {
            // History row — a quiet right-aligned relative time; the title shrinks to make room.
            let t = NSTextField(labelWithString: time)
            t.translatesAutoresizingMaskIntoConstraints = false
            t.font = Palette.metaFont
            t.textColor = Palette.textTertiary
            t.backgroundColor = .clear
            t.isBordered = false
            t.alignment = .right
            t.setContentHuggingPriority(.required, for: .horizontal)
            t.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(t)
            labelTrailing.isActive = false
            NSLayoutConstraint.activate([
                t.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                t.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: t.leadingAnchor, constant: -8),
            ])
            timeView = t
        } else if let slot {
            let c = ChipView(text: "⌘\(slot)", kind: .hud)
            addSubview(c)
            labelTrailing.isActive = false
            NSLayoutConstraint.activate([
                c.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                c.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: c.leadingAnchor, constant: -8),
            ])
            chip = c
        }
        renderTitle()
    }

    /// The armed row lifts its title secondary→primary — a core Lightfall cue (luminance, not weight).
    /// Weight stays constant across selection; only colour + the row rail/fill change.
    func setSelected(_ isSelected: Bool) {
        guard isSelected != selected else { return }
        selected = isSelected
        renderTitle()
    }

    private func renderTitle() {
        let base = selected ? Palette.textPrimary : Palette.textSecondary
        if currentQuery.isEmpty {
            label.attributedStringValue = NSAttributedString(
                string: currentName, attributes: [.font: Palette.rowTitleFont, .foregroundColor: base])
        } else {
            label.attributedStringValue = highlight(currentName, query: currentQuery, base: base)
        }
    }

    private func highlight(_ name: String, query: String, base: NSColor) -> NSAttributedString {
        let attr = NSMutableAttributedString(
            string: name, attributes: [.font: Palette.rowTitleFont, .foregroundColor: base])
        let lowerName = Array(name.lowercased())
        let lowerQuery = Array(query.lowercased())
        var qi = 0
        for (i, ch) in lowerName.enumerated() {
            if qi < lowerQuery.count && ch == lowerQuery[qi] {
                // Matched chars: heavier (SemiBold, in-family) + pure white. Weight + brightness only.
                attr.addAttributes([.font: Palette.monoSemibold(14), .foregroundColor: Palette.matched],
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
    private var captionLabel: NSTextField!
    private var pinnedContainer: NSView!
    private var pinnedLabel: NSTextField!
    private var pinnedContainerHeightConstraint: NSLayoutConstraint!
    private var pinnedCardViews: [PinnedCardView] = []
    private var scrollView: NSScrollView!
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!
    private var footerLabel: NSTextField!
    // Preview pane (⇥ toggle, browse-mode only) — read-only raw body of the selected prompt,
    // collapsed by default (previewHeightConstraint starts at 0). Grows DOWNWARD via resizePanel()'s
    // top-edge anchor, so the filter field + list above never move.
    private var previewContainer: NSScrollView!
    private var previewTextView: NSTextView!
    private var previewHeightConstraint: NSLayoutConstraint!

    private var results: [Prompt] = []
    /// Pinned prompts matching the current filter — a glanceable strip on top of the full
    /// searchable list below. Recomputed live every keystroke (unlike `hudAssignment`, which
    /// stays frozen for the appearance); pinned status is purely organizational, not part of
    /// the no-live-reshuffle hotkey-firing contract.
    private var pinnedResults: [Prompt] = []
    private var selectedIndex = 0
    private var query: String { filterField?.stringValue ?? "" }
    private var committing = false
    // Part A: ⇥ toggles a read-only preview of the selected prompt's body. Tracks the user's
    // *intent* — it can stay true while there's transiently nothing to show (State C); OFF by
    // default on every present() so a fresh open adds zero latency.
    private var previewOpen = false
    // Part B: a third palette mode showing fire-history (recency-desc) instead of the library.
    // Entered from the menu-bar "Recent History…" item; esc exits back to browse.
    private var historyMode = false
    /// filename → last-used, populated only in history mode, for the trailing per-row time label.
    private var historyDates: [String: Date] = [:]
    /// Set while `applySelectionHighlighting()` programmatically drives `tableView`'s selection,
    /// so `tableViewSelectionDidChange` can tell that apart from a real mouse click and not loop
    /// back into `selectedIndex`.
    private var syncingTableSelection = false

    // Stage 4: in-place {{ask:label}} fill-in. Non-nil only while the panel is in ask mode —
    // the same surface, the field repurposed as the answer box, the panel frame FROZEN.
    private var askFlow: AskFlow?
    private var askPrompt: Prompt?
    private var isAsking: Bool { askFlow != nil }

    // Stage 7: ⌘1–9 slot → prompt, FROZEN at present-time and held until dismiss (no live
    // reshuffle — FEATURES §7). ⌘3 fires the same prompt for the whole appearance, even while
    // the filter changes the visible rows.
    private var hudAssignment: [Int: Prompt] = [:]
    // Frozen alongside `hudAssignment` (same appearance, same freeze invariant) — filename →
    // hotkey, for the row chip lookup. Never recomputed live from the store (which could diverge
    // mid-appearance if hotkeys change on disk via the Library window).
    private var hudSlotByFilename: [String: Int] = [:]

    private static let browseFooter = "↑/↓ move · ↵ paste · ⌘E edit · ⌘1–9 quick · esc dismiss"
    private static let askFooter    = "↵ / ⇥ next · esc cancel"
    private static let historyFooter = "↑/↓ move · ↵ paste · ⌘E edit · esc back"

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
        content.layer?.backgroundColor = Palette.surface0.cgColor
        content.layer?.cornerRadius = Palette.Radius.container
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Palette.panelEdgeInner.cgColor
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
        filterField.setAccessibilityLabel("Search prompts")
        content.addSubview(filterField)

        // Separator
        separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.fillColor = Palette.separator
        content.addSubview(separator)

        // Micro-caption — a quiet section label above the viewport for instant state orientation
        // ('RECENT' / 'N MATCHES'), held at a constant height so it never shifts the input.
        captionLabel = NSTextField(labelWithString: "")
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.font = Palette.sectionLabelFont
        captionLabel.textColor = Palette.textSecondary
        captionLabel.backgroundColor = .clear
        captionLabel.isBordered = false
        content.addSubview(captionLabel)

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
        footerLabel = NSTextField(labelWithString: Self.browseFooter)
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = Palette.footerKeyFont
        footerLabel.textColor = Palette.footer
        footerLabel.alignment = .center
        footerLabel.backgroundColor = .clear
        footerLabel.isBordered = false
        content.addSubview(footerLabel)

        // Preview pane (⇥ toggle) — a read-only NSTextView in a scroll view, sitting BETWEEN the
        // results list and the footer. Collapsed (height 0) by default; `updatePreview()` measures
        // the body and grows it downward, clamped to kPreviewMaxHeight (scroll beyond).
        previewTextView = NSTextView()
        previewTextView.minSize = NSSize(width: 0, height: 0)
        previewTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        previewTextView.isVerticallyResizable = true
        previewTextView.isHorizontallyResizable = false
        previewTextView.autoresizingMask = .width
        previewTextView.textContainer?.widthTracksTextView = true
        previewTextView.isEditable = false
        previewTextView.isSelectable = false            // never grab focus off the filter field
        previewTextView.drawsBackground = false
        previewTextView.backgroundColor = .clear
        previewTextView.font = Palette.mono(13)
        previewTextView.textColor = Palette.primary
        previewTextView.textContainerInset = NSSize(width: 16, height: 8)   // align with the 16pt list inset
        previewTextView.setAccessibilityLabel("Prompt preview")

        previewContainer = NSScrollView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.hasVerticalScroller = false
        previewContainer.drawsBackground = false
        previewContainer.backgroundColor = .clear
        previewContainer.documentView = previewTextView
        content.addSubview(previewContainer)

        // Pin the list height explicitly so Auto Layout can never squeeze it to
        // zero. Updated per state in `applyState()`.
        scrollHeightConstraint = scrollView.heightAnchor.constraint(
            equalToConstant: CGFloat(kMaxRows) * kRowHeight)
        // Zero by default (no pins yet); `rebuildPinnedCards()` grows it to fit.
        pinnedContainerHeightConstraint = pinnedContainer.heightAnchor.constraint(equalToConstant: 0)
        // Zero by default (preview closed); `updatePreview()` grows it to fit the body.
        previewHeightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            scrollHeightConstraint,
            pinnedContainerHeightConstraint,
            previewHeightConstraint,

            filterField.topAnchor.constraint(equalTo: content.topAnchor),
            filterField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            filterField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            filterField.heightAnchor.constraint(equalToConstant: kFilterHeight),

            separator.topAnchor.constraint(equalTo: filterField.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: kSeparatorHeight),

            captionLabel.topAnchor.constraint(equalTo: separator.bottomAnchor),
            captionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            captionLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            captionLabel.heightAnchor.constraint(equalToConstant: kCaptionHeight),

            pinnedContainer.topAnchor.constraint(equalTo: captionLabel.bottomAnchor),
            pinnedContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pinnedContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: pinnedContainer.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            // Preview sits between the list and the footer; height driven by previewHeightConstraint.
            previewContainer.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            footerLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor),
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
        previewOpen = false   // preview is off by default every fresh open (zero added latency)
        historyMode = false
        restoreBrowseChrome()
        filterField.stringValue = ""
        refreshResults()
        // Freeze the ⌘1–9 assignment for this appearance — a hotkey is purely an explicit
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
        // Content is legible on frame 1 — never fade content in. The appear is a scale/shadow settle,
        // not an opacity ramp (protects the instant-feel).
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(filterField)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let layer = panel.contentView?.layer {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.98
            scale.toValue = 1.0
            scale.duration = 0.11
            scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            layer.add(scale, forKey: "entrance")
        }
    }

    /// Opens the palette already in history mode — the menu-bar "Recent History…" entry point.
    /// Mirrors `present`, then flips into history mode (which re-sources rows + swaps chrome).
    func presentHistory(captured: CapturedApp) {
        present(captured: captured)
        enterHistoryMode()
    }

    func dismiss() {
        panel.orderOut(nil)
        onDismiss?()
    }

    /// Pre-composite the panel offscreen so the first ⌥Space reveals an already-rendered frame
    /// (0 added latency at reveal — graft from the "material depth" direction). No-op while visible
    /// or before the store is wired.
    func warm() {
        guard promptStore != nil, !panel.isVisible else { return }
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.setFrameOrigin(origin)
    }

    func dismissAfterSuccessfulPaste() {
        commitAnimation { [weak self] in self?.dismiss() }
    }

    func showFailure(message: String) {
        // Loud, honest failure: the panel does NOT fade and does NOT auto-dismiss. The list stays
        // put; only the footer is replaced by the honest line, and esc dismisses (invariant 3).
        committing = false
        footerLabel.isHidden = false
        footerLabel.attributedStringValue = failureFooter(message)
        NSAccessibility.post(element: panel as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func failureFooter(_ message: String) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: "! ", attributes: [.font: Palette.monoSemibold(11), .foregroundColor: Palette.textPrimary])
        s.append(NSAttributedString(
            string: message, attributes: [.font: Palette.footerKeyFont, .foregroundColor: Palette.textPrimary]))
        return s
    }

    // MARK: Results / state

    private func refreshResults() {
        if historyMode {
            // History rows come from the fire-history subset (recency-desc, never-used excluded),
            // filtered by the same fuzzy match. No pinned strip here — it's a focused usage view.
            let pairs = promptStore.filterHistory(query)
            results = pairs.map { $0.0 }
            pinnedResults = []
            historyDates = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.filename, $0.1) })
        } else {
            let filtered = promptStore.filter(query)
            results = filtered
            pinnedResults = PromptStore.sortedByHotkey(filtered.filter { $0.pinned })
            historyDates = [:]
        }
        selectedIndex = 0
        rebuildPinnedCards()
        applyState()
        updatePreview()   // collapse when nothing is armed; re-render the new top row otherwise
    }

    private func applyState() {
        let libraryEmpty = promptStore.prompts.isEmpty

        if libraryEmpty {
            // State A0 — empty library (distinct from a query that found nothing).
            captionLabel.stringValue = ""
            showEmpty("No prompts yet — open the Library (⌘L) to add one")
        } else if results.isEmpty {
            // State C — no match. One quiet line, never an error colour, never a shake.
            captionLabel.stringValue = ""
            if historyMode && query.isEmpty {
                showEmpty("No history yet — prompts you fire will show here")
            } else {
                showEmpty("No match for \u{201C}\(query)\u{201D}")
            }
        } else {
            // State A (recents) / B (filtering) / history.
            captionLabel.stringValue = historyMode
                ? "HISTORY"
                : (query.isEmpty ? "RECENT" : "\(results.count) MATCH\(results.count == 1 ? "" : "ES")")
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
        updatePreview()   // an open preview tracks the armed pinned card
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
        kFilterHeight + kSeparatorHeight + kCaptionHeight
            + pinnedContainerHeightConstraint.constant + listHeight()
            + previewHeightConstraint.constant + kFooterHeight
    }

    private func resizePanel() {
        let h = panelHeight()
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = h
        frame.origin.y = top - h   // keep the top edge anchored
        panel.setFrame(frame, display: true)
    }

    // MARK: Preview pane (⇥ toggle — browse mode only)

    /// ⇥ flips the preview open/closed. Inert in history mode (the preview is a browse affordance),
    /// so the history footer/keystrokes are never disturbed.
    private func togglePreview() {
        guard !historyMode else { return }
        previewOpen.toggle()
        updatePreview()
        updateBrowseFooter()
    }

    /// Re-renders the preview for the current selection and resizes the panel (downward, top-edge
    /// anchored) to match. `previewOpen` is the user's intent; this folds in whether there's actually
    /// something to show, so an empty/no-match state collapses the pane without losing that intent.
    /// Inert while a commit is animating.
    private func updatePreview() {
        guard !committing else { return }
        guard previewOpen, let prompt = selectedPrompt else {
            previewHeightConstraint.constant = 0
            resizePanel()
            return
        }
        // Base body in primary; every {{…}} token span dimmed to tertiary so tokens read as distinct
        // machinery. spans() is pure/microsecond-scale over the already-in-memory body.
        let body = prompt.body
        let attr = NSMutableAttributedString(
            string: body, attributes: [.font: Palette.mono(13), .foregroundColor: Palette.primary])
        for span in TokenEngine.spans(in: body) {
            attr.addAttribute(.foregroundColor, value: Palette.textTertiary,
                              range: NSRange(span.range, in: body))
        }
        previewTextView.textStorage?.setAttributedString(attr)
        previewTextView.scrollRangeToVisible(NSRange(location: 0, length: 0))   // always start at top
        if let container = previewTextView.textContainer {
            previewTextView.layoutManager?.ensureLayout(for: container)
            let used = previewTextView.layoutManager?.usedRect(for: container) ?? .zero
            let contentHeight = ceil(used.height) + previewTextView.textContainerInset.height * 2
            previewHeightConstraint.constant = min(contentHeight, kPreviewMaxHeight)
        }
        resizePanel()
    }

    // MARK: History mode (menu entry point; esc exits back to browse)

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

    // MARK: Selection

    private func moveSelection(_ delta: Int) {
        let total = pinnedResults.count + results.count
        guard total > 0 else { return }
        selectedIndex = max(0, min(total - 1, selectedIndex + delta))
        applySelectionHighlighting()
        updatePreview()   // an open preview tracks the armed row
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

    /// ⌘N — fire the prompt frozen at HUD slot N (Stage 7). Honors the freeze: works against the
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
        // An open preview has no place under the ask progress line — collapse it first. When the
        // preview was already closed (the common case) this is a no-op and the frame stays frozen;
        // only an open preview shrinks, from the top, so nothing above it jumps.
        previewOpen = false
        updatePreview()
        // Repurpose the SAME surface: hide the list AND the pinned strip, keep the panel
        // exactly where/what size it is (do NOT call resizePanel — spatial trust, FEATURES §7),
        // turn the field into the answer box, and use the vacated space for a quiet progress line.
        scrollView.isHidden = true
        pinnedContainer.isHidden = true
        captionLabel.stringValue = ""
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
        // An ask can be fired from history mode too — return to whichever mode we came from.
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

    /// Browse footer with the ⇥-preview hint appended (reflecting the open/closed state).
    private func updateBrowseFooter() {
        footerLabel.stringValue = Self.browseFooter + (previewOpen ? " · ⇥ hide preview" : " · ⇥ preview")
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
                if let layer = self.panel.contentView?.layer {
                    let s = CABasicAnimation(keyPath: "transform.scale")
                    s.fromValue = 1.0
                    s.toValue = 0.985
                    s.duration = 0.12
                    s.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
                    layer.add(s, forKey: "commitScale")
                }
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
            else if historyMode { exitHistoryMode() }       // esc leaves history back to browse
            else { dismiss() }
            return true
        case #selector(NSResponder.insertNewline(_:)):      // ↵
            if isAsking { askAdvance() } else { commitSelected() }
            return true
        case #selector(NSResponder.insertTab(_:)):          // ⇥ — advances an ask, else toggles preview
            if isAsking { askAdvance() } else { togglePreview() }
            return true
        case #selector(NSResponder.moveUp(_:)):             // ↑
            if isAsking { return true }                     // no list in ask mode — swallow
            moveSelection(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):           // ↓
            if isAsking { return true }
            moveSelection(1)
            return true
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
        // History mode: trailing relative-time on each row, no ⌘-chip. Browse mode: the ⌘-chip
        // shows whenever this exact prompt has an explicit hotkey — from the FROZEN hudAssignment,
        // not live, so it can't retarget mid-appearance; independent of the current filter text
        // (a hotkey is a fixed fact about the prompt, not a ranking guess).
        let time = historyMode ? historyDates[prompt.filename].map { RelativeTime.format($0, now: Date()) } : nil
        let slot = historyMode ? nil : hudSlotByFilename[prompt.filename]
        cell.configure(name: prompt.name, query: query, slot: slot, time: time)
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
        updatePreview()   // an open preview tracks a mouse-selected row
    }
}

// MARK: - NSTextFieldDelegate conformance

extension PanelController: NSTextFieldDelegate {}
