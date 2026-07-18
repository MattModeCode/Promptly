import AppKit

// LibraryWindowController.swift — Stage 9 three-pane Library window.
//
// OFF-PASTE-PATH INVARIANT: this window is a normal, focus-taking `NSWindow`. That is safe,
// and ONLY safe, because it never participates in the ⌥Space paste loop — it never calls
// `Capture`, never calls `PanelController.present()`, never calls `PasteService`. It only
// browses, searches, creates, edits, organizes, and pins, writing through `PromptStore` (which
// writes files + reloads). If a future change ever makes this window call any of those three,
// this invariant is void and the "never steal focus" design is broken. See DESIGN.md §5.1.

/// Drag payload for moving a prompt between folders (Stage 9): the list drags a prompt's
/// `filename` (its ~/Prompts-relative path), the sidebar accepts it onto a folder row. File-scoped
/// so both the source (`ListViewController`) and target (`SidebarViewController`) VCs — which both
/// live in this file — share one type identifier. Local-only drag (never leaves the app).
private let promptDragType = NSPasteboard.PasteboardType("com.promptly.prompt.filename")

// MARK: - Sidebar

private struct SidebarRowItem {
    enum Kind: Equatable { case scope(LibraryScope), header, newFolder }
    let kind: Kind
    let label: String
    let count: Int?
}

private final class SidebarRowCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let countLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        [label, countLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.backgroundColor = .clear
            $0.isBordered = false
            addSubview($0)
        }
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: SidebarRowItem) {
        label.stringValue = item.label
        countLabel.isHidden = item.count == nil
        countLabel.stringValue = item.count.map(String.init) ?? ""
        countLabel.textColor = Palette.footer
        switch item.kind {
        case .header:
            label.font = Palette.mono(11)
            label.textColor = Palette.footer
        case .newFolder:
            label.font = Palette.mono(12)
            label.textColor = Palette.secondary
        case .scope(.folder):
            label.font = Palette.mono(12)
            label.textColor = Palette.primary
            // Folder rows nest under the "folders" header — reuse the leading inset via an
            // extra leading space rather than a second constraint set (kept simple on purpose).
            label.stringValue = "  " + item.label
        case .scope:
            label.font = Palette.mono(13)
            label.textColor = Palette.primary
        }
    }
}

private final class SidebarViewController: NSViewController {
    var onSelectScope: ((LibraryScope) -> Void)?
    var onNewFolder: (() -> Void)?
    var onDeleteFolder: ((String) -> Void)?
    var onRenameFolder: ((String) -> Void)?
    /// Fired when a prompt is dropped onto a folder row — `filename` (the dragged prompt) moves
    /// into `toFolder` ("" = root). Wired to `LibraryWindowController.movePrompt`.
    var onMovePrompt: ((_ filename: String, _ toFolder: String) -> Void)?

    private var tableView: NSTableView!
    private var rows: [SidebarRowItem] = []
    private var suppressSelectionCallback = false

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        container.wantsLayer = true
        container.layer?.backgroundColor = Palette.panelBG.cgColor

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 32
        tableView.dataSource = self
        tableView.delegate = self
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        // Right-click "Rename Folder…" / "Delete Folder…" — only shown when the clicked row is a
        // folder (see `menuNeedsUpdate`, which gates both items as a pair).
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Rename Folder…", action: #selector(renameFolderMenuAction), keyEquivalent: "")
        menu.addItem(withTitle: "Delete Folder…", action: #selector(deleteFolderMenuAction), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        tableView.menu = menu

        // Accept a prompt dragged from the middle list onto a folder row (Stage 9 move).
        tableView.registerForDraggedTypes([promptDragType])

        let scroll = NSScrollView(frame: container.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        container.addSubview(scroll)
        view = container
    }

    /// The single column is created without an explicit width, so it starts at AppKit's default
    /// (100pt) and only catches up to the pane's real width once a resize event fires — which can
    /// lag behind the split view's initial layout. Force it to track the actual width on every
    /// layout pass so labels (e.g. "+ new folder") don't truncate just because the column hasn't
    /// caught up yet.
    override func viewDidLayout() {
        super.viewDidLayout()
        tableView.sizeLastColumnToFit()
    }

    func reload(prompts: [Prompt], freshFolders: Set<String>, selected: LibraryScope) {
        let pinnedCount = prompts.filter { $0.pinned }.count
        var items: [SidebarRowItem] = [
            SidebarRowItem(kind: .scope(.all), label: "all", count: prompts.count),
            SidebarRowItem(kind: .scope(.pinned), label: "pinned", count: pinnedCount),
            SidebarRowItem(kind: .scope(.recent), label: "recent", count: nil),
        ]
        let folderNames = Set(prompts.map { $0.folder }.filter { !$0.isEmpty }).union(freshFolders)
        if !folderNames.isEmpty {
            items.append(SidebarRowItem(kind: .header, label: "folders", count: nil))
            for name in folderNames.sorted() {
                let count = prompts.filter { $0.folder == name }.count
                items.append(SidebarRowItem(kind: .scope(.folder(name)), label: name, count: count))
            }
        }
        items.append(SidebarRowItem(kind: .newFolder, label: "+ new folder", count: nil))
        rows = items
        tableView.reloadData()
        suppressSelectionCallback = true
        if let idx = rows.firstIndex(where: { $0.kind == .scope(selected) }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
        suppressSelectionCallback = false
    }
}

extension SidebarViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? SidebarRowCellView) ?? {
            let c = SidebarRowCellView(); c.identifier = id; return c
        }()
        cell.configure(rows[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].kind != .header
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count else { return }
        switch rows[row].kind {
        case .scope(let scope): onSelectScope?(scope)
        case .newFolder: onNewFolder?()
        case .header: break
        }
    }

    // MARK: Drop target (prompt → folder move, Stage 9)

    /// The folder a prompt dropped onto sidebar row `row` should move INTO, or nil if that row
    /// rejects prompt drops (headers, "+ new folder", the virtual `.pinned`/`.recent` scopes).
    /// `.all` resolves to "" — a valid drop that moves the prompt to the root.
    private func dropDestinationFolder(forRow row: Int) -> String? {
        guard row >= 0, row < rows.count, case .scope(let s) = rows[row].kind else { return nil }
        return LibraryScope.dropDestination(s)
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropDestinationFolder(forRow: row) != nil else { return [] }
        tableView.setDropRow(row, dropOperation: .on)
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let filename = info.draggingPasteboard.string(forType: promptDragType),
              let dest = dropDestinationFolder(forRow: row) else { return false }
        onMovePrompt?(filename, dest)
        return true
    }
}

extension SidebarViewController: NSMenuDelegate {
    /// Only show the folder actions ("Rename Folder…" / "Delete Folder…") when the right-clicked
    /// row is an actual folder row — hide/show them as a pair.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = tableView.clickedRow
        let isFolderRow: Bool
        if row >= 0, row < rows.count, case .scope(.folder) = rows[row].kind {
            isFolderRow = true
        } else {
            isFolderRow = false
        }
        for item in menu.items { item.isHidden = !isFolderRow }
    }

    @objc fileprivate func renameFolderMenuAction() {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, case .scope(.folder(let name)) = rows[row].kind else { return }
        onRenameFolder?(name)
    }

    @objc fileprivate func deleteFolderMenuAction() {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, case .scope(.folder(let name)) = rows[row].kind else { return }
        onDeleteFolder?(name)
    }
}

// MARK: - Middle list

private final class PromptListCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let descLabel = NSTextField(labelWithString: "")
    /// Right cluster — pin glyph + hotkey chip (info-forward, strict monochrome). Rebuilt per row.
    private let rightStack = NSStackView()

    init() {
        super.init(frame: .zero)
        titleLabel.font = Palette.cardTitleFont
        titleLabel.textColor = Palette.primary
        titleLabel.lineBreakMode = .byTruncatingTail
        descLabel.font = Palette.secondaryFont
        descLabel.textColor = Palette.secondary
        descLabel.lineBreakMode = .byTruncatingTail
        [titleLabel, descLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.backgroundColor = .clear
            $0.isBordered = false
            addSubview($0)
        }
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.orientation = .horizontal
        rightStack.spacing = 6
        rightStack.alignment = .centerY
        rightStack.setContentHuggingPriority(.required, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(rightStack)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            descLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightStack.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ prompt: Prompt) {
        titleLabel.stringValue = prompt.name
        descLabel.stringValue = prompt.description ?? " "
        rightStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if prompt.pinned, #available(macOS 11.0, *),
           let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned") {
            pin.isTemplate = true
            let iv = NSImageView(image: pin)
            iv.contentTintColor = Palette.textTertiary
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            rightStack.addArrangedSubview(iv)
        }
        if let hotkey = prompt.hotkey {
            rightStack.addArrangedSubview(ChipView(text: "⌘\(hotkey)", kind: .keycap))
        }
    }
}

private final class ListViewController: NSViewController {
    var onSelectPrompt: ((Prompt) -> Void)?
    var onFilterChanged: ((String) -> Void)?
    var onNewPrompt: (() -> Void)?

    private var newPromptButton: ThemedButton!
    private var filterField: NSTextField!
    private var tableView: NSTableView!
    private(set) var prompts: [Prompt] = []
    private var suppressSelectionCallback = false

    var filterText: String { filterField?.stringValue ?? "" }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        container.wantsLayer = true
        container.layer?.backgroundColor = Palette.panelBG.cgColor

        newPromptButton = ThemedButton(title: "+ New Prompt", style: .standard, target: self, action: #selector(newPromptPressed))
        container.addSubview(newPromptButton)

        filterField = NSTextField()
        filterField.placeholderAttributedString = NSAttributedString(
            string: "Search", attributes: [.font: Palette.mono(13), .foregroundColor: Palette.footer])
        filterField.font = Palette.mono(13)
        filterField.textColor = Palette.primary
        filterField.backgroundColor = Palette.panelBG
        filterField.drawsBackground = true
        filterField.isBordered = false
        filterField.focusRingType = .none
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.delegate = self
        container.addSubview(filterField)

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 56
        tableView.dataSource = self
        tableView.delegate = self
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("list"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        // Drag a prompt out to the sidebar to move it between folders (Stage 9). Local-only.
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            newPromptButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            newPromptButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            newPromptButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            filterField.topAnchor.constraint(equalTo: newPromptButton.bottomAnchor, constant: 8),
            filterField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            filterField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            filterField.heightAnchor.constraint(equalToConstant: 26),

            scroll.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    @objc private func newPromptPressed() {
        onNewPrompt?()
    }

    func reload(_ prompts: [Prompt], selecting filename: String?) {
        self.prompts = prompts
        tableView.reloadData()
        suppressSelectionCallback = true
        if let filename, let idx = prompts.firstIndex(where: { $0.filename == filename }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
        suppressSelectionCallback = false
    }

    func focusFilter() {
        view.window?.makeFirstResponder(filterField)
    }
}

extension ListViewController: NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { prompts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("PromptListCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PromptListCellView) ?? {
            let c = PromptListCellView(); c.identifier = id; return c
        }()
        cell.configure(prompts[row])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < prompts.count else { return }
        onSelectPrompt?(prompts[row])
    }

    /// Provide the dragged prompt's `filename` on the pasteboard so the sidebar can move it into
    /// a folder (Stage 9). Only `filename` travels — the target re-resolves the live `Prompt`.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(prompts[row].filename, forType: promptDragType)
        return item
    }

    func controlTextDidChange(_ obj: Notification) {
        onFilterChanged?(filterText)
    }
}

// MARK: - Detail (the editor)

private func libraryLabel(_ text: String) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = Palette.mono(11)
    f.textColor = Palette.secondary
    f.backgroundColor = .clear
    f.isBordered = false
    f.translatesAutoresizingMaskIntoConstraints = false
    return f
}

private func libraryTextField() -> NSTextField {
    // Bug A (dead fields): `LibraryField` sets the cell via `cellClass`, so AppKit builds an
    // editable/selectable cell — unlike the old `f.cell = VCenterTextFieldCell()` (a bare cell
    // defaults to non-editable). Bug B (top sliver): paint the fill on the LAYER (not the cell's
    // `drawsBackground`) so it fills the whole rounded rect — no panel-bg sliver at the top edge.
    let f = LibraryField()
    f.font = Palette.mono(13)
    f.textColor = Palette.primary
    f.drawsBackground = false
    f.isBordered = false
    f.focusRingType = .none
    f.translatesAutoresizingMaskIntoConstraints = false
    f.wantsLayer = true
    f.layer?.backgroundColor = Palette.surface2.cgColor
    f.layer?.cornerRadius = Palette.Radius.control
    f.layer?.masksToBounds = true
    f.layer?.borderWidth = 1
    f.layer?.borderColor = Palette.borderDefault.cgColor
    return f
}

private final class DetailViewController: NSViewController, NSTextFieldDelegate {
    var promptStore: PromptStore!
    /// Fired after any persist/move/delete that should refresh the sidebar counts + list.
    var onChanged: (() -> Void)?
    /// Fired when a brand-new folder is created via the "New folder…" picker item, so the
    /// window can track it as freshly-created-but-empty (it has no prompt yet, so it wouldn't
    /// otherwise appear in the sidebar — see STAGE-9 §5.2).
    var onFolderCreated: ((String) -> Void)?

    var selectedFilename: String { currentFilename }

    private var titleField: NSTextField!
    private var folderPopUp: ThemedPopUp!
    private var pinButton: PinChipButton!
    private var hotkeyField: NSTextField!
    private var descriptionField: NSTextField!
    private var bodyView: NSTextView!
    private var warningLabel: NSTextField!
    private var usageLabel: NSTextField!
    private var saveButton: ThemedButton!
    private var deleteButton: ThemedButton!

    private var currentFilename = ""
    private var currentFolder = ""
    private var currentKeywords: [String] = []

    // Snapshot of the fields as of the last `load(prompt:)` or successful `persist()` — saving
    // is explicit now (no auto-save on blur), so this is what `isDirty` diffs against to warn
    // before silently discarding edits.
    private var baselineTitle = ""
    private var baselineDescription = ""
    private var baselineBody = ""
    private var baselinePinned = false
    private var baselineHotkey = ""
    private var baselineFolder = ""

    /// Hotkey/pinned/folder auto-save (see `autoSaveMetadata()`), so only title/body/description
    /// can go stale relative to disk — those are what the discard-confirmation guard cares about.
    var isDirty: Bool {
        titleField.stringValue != baselineTitle ||
            descriptionField.stringValue != baselineDescription ||
            bodyView.string != baselineBody
    }

    /// Supplies folders that exist only in memory (just created, no prompt moved into them yet) —
    /// without this, `rebuildFolderMenu()`'s derive-from-prompts logic can't see them (mirrors the
    /// sidebar's `freshFolders:` parameter, STAGE-9 §5.2).
    var extraFolders: (() -> Set<String>)?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 500))
        container.wantsLayer = true
        container.layer?.backgroundColor = Palette.panelBG.cgColor
        view = container
        buildContent()
    }

    private func buildContent() {
        let pad: CGFloat = 20
        let content = view

        let titleLabel = libraryLabel("title")
        titleField = libraryTextField()
        titleField.font = Palette.titleLgFont   // the editor's headline

        // Usage subtitle under the title — read-only meta ("used N× · last used …"), same small
        // mono/tertiary voice as the field labels. Populated by `refreshUsage()`.
        usageLabel = NSTextField(labelWithString: "")
        usageLabel.font = Palette.mono(11)
        usageLabel.textColor = Palette.footer
        usageLabel.backgroundColor = .clear
        usageLabel.isBordered = false
        usageLabel.translatesAutoresizingMaskIntoConstraints = false

        let folderLabel = libraryLabel("folder")
        folderPopUp = ThemedPopUp()
        folderPopUp.target = self
        folderPopUp.action = #selector(folderPopUpChanged)
        // Pinned on both sides now (flexes to fill the row) — let it stretch and, at the minimum
        // window width, compress/truncate rather than overflow into the hotkey box.
        folderPopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        folderPopUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        pinButton = PinChipButton()
        pinButton.onToggle = { [weak self] in self?.autoSaveMetadata() }

        let hotkeyLabel = libraryLabel("hotkey")
        hotkeyField = libraryTextField()
        hotkeyField.delegate = self
        hotkeyField.placeholderAttributedString = NSAttributedString(
            string: "1–9", attributes: [.font: Palette.mono(13), .foregroundColor: Palette.footer])

        let descLabel = libraryLabel("description")
        descriptionField = libraryTextField()

        let bodyLabel = libraryLabel("prompt body")

        warningLabel = NSTextField(labelWithString: "")
        warningLabel.font = Palette.mono(11)
        warningLabel.textColor = Palette.textPrimary   // monochrome — no warning orange (Lightfall)
        warningLabel.backgroundColor = .clear
        warningLabel.isBordered = false
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.isHidden = true

        saveButton = ThemedButton(title: "Save", style: .primary, target: self, action: #selector(savePressed))
        deleteButton = ThemedButton(title: "Delete", style: .destructive, target: self, action: #selector(deletePressed))

        // Body text view — lifted verbatim from the old PromptEditorPanel.swift (the geometry
        // there is already correct: scroll view, container sizing, widthTracksTextView, colors,
        // insertion point).
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 1.0, alpha: 0.05)
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 5
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        bodyView = NSTextView()
        bodyView.minSize = NSSize(width: 0, height: 0)
        bodyView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        bodyView.isVerticallyResizable = true
        bodyView.isHorizontallyResizable = false
        bodyView.autoresizingMask = .width
        bodyView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        bodyView.textContainer?.widthTracksTextView = true
        bodyView.backgroundColor = .clear
        bodyView.font = Palette.mono(13)
        bodyView.textColor = Palette.primary
        bodyView.insertionPointColor = Palette.primary
        bodyView.isEditable = true
        bodyView.isSelectable = true
        scroll.documentView = bodyView

        [titleLabel, titleField, usageLabel, folderLabel, folderPopUp, pinButton,
         hotkeyLabel, hotkeyField, descLabel, descriptionField, bodyLabel, scroll,
         warningLabel, saveButton, deleteButton].forEach { content.addSubview($0) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            titleField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            titleField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            titleField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            titleField.heightAnchor.constraint(equalToConstant: 28),

            // Usage subtitle sits between the title and the folder/hotkey row; those two labels
            // re-hang off its bottom so everything below flows naturally with minimal reflow.
            usageLabel.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 6),
            usageLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            folderLabel.topAnchor.constraint(equalTo: usageLabel.bottomAnchor, constant: 12),
            folderLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            folderPopUp.topAnchor.constraint(equalTo: folderLabel.bottomAnchor, constant: 4),
            folderPopUp.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            // Folder popup flexes to fill the row; the hotkey box (fixed width) and the pin chip
            // (right edge) take the rest, so the pin no longer squeezes the hotkey box.
            folderPopUp.trailingAnchor.constraint(equalTo: hotkeyField.leadingAnchor, constant: -16),
            folderPopUp.heightAnchor.constraint(equalToConstant: 28),

            // Pin chip pinned to the right edge, vertically centered on the row.
            pinButton.centerYAnchor.constraint(equalTo: folderPopUp.centerYAnchor),
            pinButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            // Hotkey: fixed width (only ever holds one digit) so it can't be cut off, top-aligned
            // with the folder popup, sitting between the popup and the pin chip.
            hotkeyLabel.topAnchor.constraint(equalTo: usageLabel.bottomAnchor, constant: 12),
            hotkeyLabel.leadingAnchor.constraint(equalTo: hotkeyField.leadingAnchor),
            hotkeyField.topAnchor.constraint(equalTo: hotkeyLabel.bottomAnchor, constant: 4),
            hotkeyField.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -16),
            hotkeyField.widthAnchor.constraint(equalToConstant: 64),
            hotkeyField.heightAnchor.constraint(equalToConstant: 28),

            descLabel.topAnchor.constraint(equalTo: folderPopUp.bottomAnchor, constant: 14),
            descLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            descriptionField.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 4),
            descriptionField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            descriptionField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            descriptionField.heightAnchor.constraint(equalToConstant: 28),

            bodyLabel.topAnchor.constraint(equalTo: descriptionField.bottomAnchor, constant: 14),
            bodyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            scroll.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            scroll.bottomAnchor.constraint(equalTo: warningLabel.topAnchor, constant: -8),

            warningLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            warningLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            warningLabel.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -8),

            deleteButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            deleteButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),

            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            saveButton.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
        ])
    }

    /// Loads a prompt into the detail fields, or a blank/pre-filled state for a new one.
    /// `prompt == nil` means "new, unsaved" — `folder`/`initialBody` seed it (the latter for
    /// ⌥⇧Space inverse-capture).
    func load(prompt: Prompt?, initialBody: String = "", folder: String = "") {
        currentFilename = prompt?.filename ?? ""
        currentFolder = prompt?.folder ?? folder
        currentKeywords = prompt?.keywords ?? []
        titleField.stringValue = prompt?.name ?? ""
        descriptionField.stringValue = prompt?.description ?? ""
        bodyView.string = prompt?.body ?? initialBody
        pinButton.isOn = prompt?.pinned ?? false
        hotkeyField.stringValue = prompt?.hotkey.map(String.init) ?? ""
        warningLabel.isHidden = true
        deleteButton.isEnabled = !currentFilename.isEmpty
        rebuildFolderMenu(selecting: currentFolder)
        captureBaseline()
        if prompt == nil {
            view.window?.makeFirstResponder(titleField)
        }
        refreshUsage()
    }

    /// Refreshes the read-only usage subtitle from the store. Hidden for an unsaved prompt (no
    /// filename ⇒ no usage key yet); otherwise "used N× · last used …", or "not yet used" when the
    /// prompt exists but has never been fired. Non-private so the window controller can refresh it
    /// from `handleReload()` — it's read-only, so unconditional refresh can't clobber an edit.
    func refreshUsage() {
        guard !currentFilename.isEmpty else { usageLabel.isHidden = true; return }
        usageLabel.isHidden = false
        usageLabel.stringValue = promptStore.usage(for: currentFilename).map {
            RelativeTime.usageSummary(count: $0.count, lastUsed: $0.lastUsed, now: Date())
        } ?? "not yet used"
    }

    /// Hotkey is auto-saved (unlike title/body/description) — commit on blur rather than waiting
    /// for the explicit Save button.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === hotkeyField else { return }
        autoSaveMetadata()
    }

    private func captureBaseline() {
        baselineTitle = titleField.stringValue
        baselineDescription = descriptionField.stringValue
        baselineBody = bodyView.string
        baselinePinned = pinButton.isOn
        baselineHotkey = hotkeyField.stringValue
        baselineFolder = currentFolder
    }

    private func rebuildFolderMenu(selecting folder: String) {
        let folders = Set(promptStore.prompts.map { $0.folder }).filter { !$0.isEmpty }
            .union(extraFolders?() ?? [])
        folderPopUp.removeAllItems()
        folderPopUp.addItem(withTitle: "General")
        for f in folders.sorted() { folderPopUp.addItem(withTitle: f) }
        folderPopUp.addItem(withTitle: "New folder…")
        folderPopUp.selectItem(withTitle: folder.isEmpty ? "General" : folder)
        folderPopUp.themeItems()
    }

    @objc private func folderPopUpChanged() {
        guard let title = folderPopUp.titleOfSelectedItem else { return }
        if title == "New folder…" {
            guard let window = view.window else { rebuildFolderMenu(selecting: currentFolder); return }
            NewFolderSheet().present(over: window) { [weak self] name in
                guard let self else { return }
                if let name {
                    self.onFolderCreated?(name)
                    self.applyFolderChange(to: name)
                } else {
                    self.rebuildFolderMenu(selecting: self.currentFolder)
                }
            }
        } else {
            applyFolderChange(to: title == "General" ? "" : title)
        }
    }

    /// Folder is auto-saved (unlike title/body/description) — updates `currentFolder` and commits
    /// it immediately via `autoSaveMetadata()`, which runs the actual `PromptStore.move(_:toFolder:)`
    /// (migrating the usage key so frecency survives the reorganize, DESIGN §7.1).
    private func applyFolderChange(to folder: String) {
        guard folder != currentFolder else { return }
        currentFolder = folder
        rebuildFolderMenu(selecting: currentFolder)
        autoSaveMetadata()
    }

    @objc private func deletePressed() {
        guard !currentFilename.isEmpty,
              let prompt = promptStore.prompts.first(where: { $0.filename == currentFilename }),
              let window = view.window else { return }
        ConfirmSheet().present(over: window,
                               title: "Delete \"\(prompt.name)\"?",
                               message: "Removes the file from ~/Prompts. Cannot be undone.",
                               confirmTitle: "Delete") { [weak self] confirmed in
            guard let self, confirmed else { return }
            self.promptStore.delete(prompt)
            self.currentFilename = ""
            self.onChanged?()
        }
    }

    @objc private func savePressed() {
        persist()
    }

    /// Hotkey/pinned/folder digit/conflict resolution is shared between the auto-save path
    /// (`autoSaveMetadata()`) and the explicit Save path (`persist()`).
    private func resolvedHotkey() -> Int? {
        let raw = hotkeyField.stringValue.trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? nil : Int(raw).flatMap { PromptStore.hotkeySlots.contains($0) ? $0 : nil }
    }

    /// Commits hotkey/pinned/folder immediately on change — these three don't wait for the
    /// explicit Save button. It must NOT pick up unsaved edits to title/body/description, so it
    /// writes using the baseline (last-persisted) values for those three fields. No-ops for a
    /// not-yet-created prompt (currentFilename empty); those values just stay in memory until the
    /// first explicit Save, same as before. Hotkey conflicts resolve by a user-initiated steal —
    /// distinct from Stage 8's silent, read-only load-time handling: here the user explicitly
    /// claimed the slot, so the prior holder's file IS rewritten, and the inline warning says so.
    private func autoSaveMetadata() {
        guard !currentFilename.isEmpty,
              let existing = promptStore.prompts.first(where: { $0.filename == currentFilename }) else { return }

        if existing.folder != currentFolder {
            promptStore.move(existing, toFolder: currentFolder)
            if let moved = promptStore.prompts.first(where: { $0.name == existing.name && $0.folder == currentFolder }) {
                currentFilename = moved.filename
            }
        }

        let hotkey = resolvedHotkey()
        if let hotkey,
           let conflict = promptStore.prompts.first(where: { $0.hotkey == hotkey && $0.filename != currentFilename }) {
            promptStore.save(name: conflict.name, keywords: conflict.keywords, body: conflict.body,
                             folder: conflict.folder, pinned: conflict.pinned, hotkey: nil,
                             description: conflict.description, filename: conflict.filename)
            warningLabel.stringValue = "⌘\(hotkey) was on '\(conflict.name)' — moved here"
            warningLabel.isHidden = false
        }

        promptStore.save(name: baselineTitle, keywords: currentKeywords, body: baselineBody,
                         folder: currentFolder, pinned: pinButton.isOn, hotkey: hotkey,
                         description: baselineDescription.isEmpty ? nil : baselineDescription,
                         filename: currentFilename)

        baselinePinned = pinButton.isOn
        baselineHotkey = hotkeyField.stringValue
        baselineFolder = currentFolder
    }

    /// Writes title/description/body through `PromptStore.save(...)`, called only from the
    /// explicit Save button — there is no auto-save on field blur for these three. Hotkey/pinned/
    /// folder are passed through as their current (already auto-saved) values.
    private func persist() {
        let name = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            warningLabel.stringValue = "Title required."
            warningLabel.isHidden = false
            return
        }
        warningLabel.isHidden = true

        let description = descriptionField.stringValue.trimmingCharacters(in: .whitespaces)
        let body = bodyView.string

        promptStore.save(name: name, keywords: currentKeywords, body: body, folder: currentFolder,
                         pinned: pinButton.isOn, hotkey: resolvedHotkey(),
                         description: description.isEmpty ? nil : description,
                         filename: currentFilename)

        if let saved = promptStore.prompts.first(where: { $0.name == name && $0.folder == currentFolder }) {
            currentFilename = saved.filename
            currentKeywords = saved.keywords
            deleteButton.isEnabled = true
        }
        captureBaseline()
        refreshUsage()
        onChanged?()
    }
}

// MARK: - The window

final class LibraryWindowController: NSWindowController {
    private let promptStore: PromptStore
    private let sidebarVC = SidebarViewController()
    private let listVC = ListViewController()
    private let detailVC = DetailViewController()
    private var scope: LibraryScope = .all
    /// Folders that exist only in memory (just created, no prompt moved into them yet) — the
    /// sidebar otherwise derives folder rows purely from loaded prompts, so a just-created empty
    /// folder would vanish without this (STAGE-9 §5.2).
    private var freshlyCreatedEmptyFolders: Set<String> = []

    /// Fired before the window comes to front (all three public show paths funnel through
    /// `show()`) — `main.swift` uses this to dismiss the HUD palette first. Without it, the HUD's
    /// `.floating`-level panel can sit on top of this (`.normal`-level) window wherever their
    /// frames happen to overlap, silently swallowing clicks meant for the editor's fields.
    var onWillShow: (() -> Void)?

    init(promptStore: PromptStore) {
        self.promptStore = promptStore
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Library"
        window.minSize = NSSize(width: 740, height: 420)
        window.backgroundColor = Palette.panelBG
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true   // titlebar blends into the surface-0 chrome
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        detailVC.promptStore = promptStore
        buildSplitView()
        wire()
        // Off the paste loop (see file header) — safe to subscribe directly; this window is the
        // only consumer of onReload (Stage 8 shipped with none).
        promptStore.onReload = { [weak self] in self?.handleReload() }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildSplitView() {
        let splitVC = NSSplitViewController()
        splitVC.splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 260
        sidebarItem.canCollapse = false
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(300)   // stays put on resize

        let listItem = NSSplitViewItem(viewController: listVC)
        listItem.minimumThickness = 220
        listItem.holdingPriority = NSLayoutConstraint.Priority(100)      // absorbs resize slack

        let detailItem = NSSplitViewItem(viewController: detailVC)
        detailItem.minimumThickness = 320
        detailItem.holdingPriority = NSLayoutConstraint.Priority(200)

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(listItem)
        splitVC.addSplitViewItem(detailItem)
        window?.contentViewController = splitVC
    }

    private func wire() {
        sidebarVC.onSelectScope = { [weak self] scope in
            self?.scope = scope
            self?.refreshList()
        }
        sidebarVC.onNewFolder = { [weak self] in self?.createFolder() }
        sidebarVC.onDeleteFolder = { [weak self] name in self?.confirmDeleteFolder(name) }
        sidebarVC.onRenameFolder = { [weak self] name in self?.promptRenameFolder(name) }
        sidebarVC.onMovePrompt = { [weak self] filename, dest in self?.movePrompt(filename, to: dest) }

        listVC.onFilterChanged = { [weak self] _ in self?.refreshList() }
        listVC.onSelectPrompt = { [weak self] prompt in
            guard let self else { return }
            self.confirmDiscardIfNeeded { discard in
                guard discard else {
                    self.refreshList()   // revert the list's visual selection back to the current prompt
                    return
                }
                self.detailVC.load(prompt: prompt)
            }
        }
        listVC.onNewPrompt = { [weak self] in
            guard let self else { return }
            self.confirmDiscardIfNeeded { discard in
                guard discard else { return }
                self.showNewPrompt()
            }
        }

        detailVC.onChanged = { [weak self] in self?.refreshList() }
        detailVC.onFolderCreated = { [weak self] name in self?.freshlyCreatedEmptyFolders.insert(name) }
        detailVC.extraFolders = { [weak self] in self?.freshlyCreatedEmptyFolders ?? [] }
    }

    /// Saving is explicit for title/body/description — without this guard, switching prompts or
    /// starting a new one would silently discard in-progress edits. Calls `onResolved(true)` if
    /// it's safe to proceed (nothing unsaved, or the user chose to discard). Uses the same themed
    /// `ConfirmSheet` as delete confirmation rather than a native `NSAlert`.
    private func confirmDiscardIfNeeded(_ onResolved: @escaping (Bool) -> Void) {
        guard detailVC.isDirty else { onResolved(true); return }
        guard let window else { onResolved(false); return }
        ConfirmSheet().present(over: window,
                               title: "Discard unsaved changes?",
                               message: "Your edits to this prompt have not been saved.",
                               confirmTitle: "Discard",
                               completion: onResolved)
    }

    /// Right-click "Delete Folder…" on the sidebar. An empty (freshly-created, never-saved-into)
    /// folder has nothing to lose — drop it from `freshlyCreatedEmptyFolders` with no sheet.
    /// Otherwise ask whether to move its prompts elsewhere or delete them all (`DeleteFolderSheet`).
    private func confirmDeleteFolder(_ name: String) {
        let count = promptStore.prompts.filter { $0.folder == name }.count
        guard count > 0 else {
            freshlyCreatedEmptyFolders.remove(name)
            if scope == .folder(name) { scope = .all }
            refreshList()
            return
        }
        guard let window else { return }
        let otherRealFolders = Set(promptStore.prompts.map { $0.folder }).filter { !$0.isEmpty && $0 != name }
        let otherFreshFolders = freshlyCreatedEmptyFolders.filter { $0 != name }
        let destinations = ["General"] + otherRealFolders.union(otherFreshFolders).sorted()
        let editingAffected = promptStore.prompts.first(where: { $0.filename == detailVC.selectedFilename })?.folder == name

        DeleteFolderSheet().present(over: window, folderName: name, promptCount: count,
                                    destinations: destinations) { [weak self] action in
            guard let self, let action else { return }
            switch action {
            case .deleteAll: self.promptStore.deleteFolder(name, moveTo: nil)
            case .moveTo(let dest): self.promptStore.deleteFolder(name, moveTo: dest)
            }
            if editingAffected { self.detailVC.load(prompt: nil) }
            if self.scope == .folder(name) { self.scope = .all }
            self.refreshList()
        }
    }

    /// Right-click "Rename Folder…" on the sidebar. A freshly-created empty folder has no files
    /// yet, so it's renamed purely in memory (swap the tracking-set entry, no disk op). A real
    /// folder goes through `PromptStore.renameFolder`, which moves the subtree and migrates usage
    /// keys. `editingAffected` is captured up front (before the store mutates `filename`s) the same
    /// way `confirmDeleteFolder` does, so the detail pane is reset only when it was showing a
    /// prompt from the renamed folder.
    private func promptRenameFolder(_ name: String) {
        guard let window else { return }
        let editingAffected = promptStore.prompts.first(where: { $0.filename == detailVC.selectedFilename })?.folder == name
        NewFolderSheet().present(over: window, title: "Rename folder", initialValue: name,
                                 confirmTitle: "Rename") { [weak self] newName in
            guard let self, let newName, newName != name else { return }
            if self.freshlyCreatedEmptyFolders.contains(name) {
                self.freshlyCreatedEmptyFolders.remove(name)
                self.freshlyCreatedEmptyFolders.insert(newName)
            } else {
                self.promptStore.renameFolder(name, to: newName)
            }
            if editingAffected { self.detailVC.load(prompt: nil) }
            if self.scope == .folder(name) { self.scope = .folder(newName) }
            self.refreshList()
        }
    }

    /// A prompt dragged from the list onto a sidebar folder row (Stage 9). No-op guard: dropping a
    /// prompt back onto its own folder must return early — otherwise `move()` would mint a
    /// collision-safe `foo-2.md` and duplicate the prompt. Otherwise `move()` handles the file +
    /// usage-key migration and reloads itself; we just refresh the list.
    private func movePrompt(_ filename: String, to dest: String) {
        guard let prompt = promptStore.prompts.first(where: { $0.filename == filename }) else { return }
        guard prompt.folder != dest else { return }
        promptStore.move(prompt, toFolder: dest)
        refreshList()
    }

    /// `PromptStore.onReload` fires on every load — both our own saves and external file
    /// changes. Always safe to refresh the sidebar/list (read-only data). The detail pane's
    /// editable fields are deliberately NOT reloaded here — only `persist()`'s own field values
    /// drive them, and re-pushing store state into a field the user might be mid-edit on is
    /// exactly the clobber the live-refresh guard exists to prevent. The usage line is read-only
    /// and safe to refresh unconditionally.
    private func handleReload() {
        refreshList()
        detailVC.refreshUsage()   // read-only meta — safe to refresh even mid-edit (see comment above)
    }

    private func refreshList() {
        // Keep only genuinely-empty in-memory folders (STAGE-9 §5.2): once a fresh folder gains a
        // prompt, the sidebar derives it from `prompts` anyway, and leaving its name here would send
        // the rename/delete paths down their in-memory branch and skip the real on-disk op.
        freshlyCreatedEmptyFolders = freshlyCreatedEmptyFolders.filter { name in !promptStore.prompts.contains { $0.folder == name } }
        let filtered = LibraryScope.filter(scope, prompts: promptStore.prompts,
                                           usage: promptStore.allUsage, query: listVC.filterText)
        let selecting = detailVC.selectedFilename.isEmpty ? nil : detailVC.selectedFilename
        listVC.reload(filtered, selecting: selecting)
        sidebarVC.reload(prompts: promptStore.prompts, freshFolders: freshlyCreatedEmptyFolders, selected: scope)
    }

    private func createFolder() {
        guard let window else { return }
        NewFolderSheet().present(over: window) { [weak self] name in
            guard let self else { return }
            guard let name else {
                self.sidebarVC.reload(prompts: self.promptStore.prompts,
                                      freshFolders: self.freshlyCreatedEmptyFolders, selected: self.scope)
                return
            }
            self.freshlyCreatedEmptyFolders.insert(name)
            self.scope = .folder(name)
            self.refreshList()
        }
    }

    private func show() {
        onWillShow?()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - Public API (main.swift)

    /// Menu-bar "Library…" — the `all` scope, filter focused.
    func showLibrary() {
        scope = .all
        refreshList()
        show()
        listVC.focusFilter()
    }

    /// Menu-bar "New Prompt…" / ⌥⇧Space inverse-capture — a blank detail, root folder,
    /// optionally pre-filled with a captured selection as the body.
    func showNewPrompt(initialBody: String = "") {
        detailVC.load(prompt: nil, initialBody: initialBody, folder: "")
        refreshList()
        show()
    }

    /// `panelController.onEdit` (⌘E from the palette) — open focused on that prompt.
    func show(editing prompt: Prompt) {
        scope = .all
        detailVC.load(prompt: prompt)
        refreshList()
        show()
    }
}
