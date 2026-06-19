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

// MARK: - Filter field (key interception)

final class FilterField: NSTextField {
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onDeleteWhenEmpty: (() -> Void)?
    var onEdit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onUp?()        // ↑
        case 125: onDown?()      // ↓
        case 36:  onReturn?()    // ↵
        case 53:  onEscape?()    // esc
        case 51:                 // ⌫ backspace — delete selected when filter is empty
            if stringValue.isEmpty { onDeleteWhenEmpty?() } else { super.keyDown(with: event) }
        case 14 where event.modifierFlags.contains(.command): // ⌘E — edit selected
            onEdit?()
        default:  super.keyDown(with: event)
        }
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
    var onCommit: ((Prompt) -> Void)?
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
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!
    private var footerLabel: NSTextField!

    private var results: [Prompt] = []
    private var selectedIndex = 0
    private var query: String { filterField?.stringValue ?? "" }
    private var committing = false

    override init() {
        super.init()
        buildPanel()
    }

    // MARK: Build

    private func buildPanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: kPanelWidth, height: 300),
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
        filterField.onUp = { [weak self] in self?.moveSelection(-1) }
        filterField.onDown = { [weak self] in self?.moveSelection(1) }
        filterField.onReturn = { [weak self] in self?.commitSelected() }
        filterField.onEscape = { [weak self] in self?.dismiss() }
        filterField.onDeleteWhenEmpty = { [weak self] in self?.confirmDeleteSelected() }
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

        NSLayoutConstraint.activate([
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
        resizePanel()
    }

    private func showEmpty(_ text: String) {
        emptyLabel.stringValue = text
        emptyLabel.isHidden = false
        scrollView.isHidden = true
    }

    private func panelHeight() -> CGFloat {
        let rowsArea: CGFloat
        if promptStore.prompts.isEmpty || results.isEmpty {
            rowsArea = kRowHeight   // one line for the empty/no-match message
        } else {
            rowsArea = CGFloat(min(results.count, kMaxRows)) * kRowHeight
        }
        return kFilterHeight + kSeparatorHeight + rowsArea + kFooterHeight
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
        committing = true
        let prompt = results[selectedIndex]
        // State D drops the footer immediately; the paste itself is driven by onCommit, which
        // calls back into dismissAfterSuccessfulPaste / showFailure.
        footerLabel.isHidden = true
        onCommit?(prompt)
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
        refreshResults()
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
