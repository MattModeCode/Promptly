# Stage 9 — Three-pane Library window (replaces the modal editor)

**Status:** Forward spec (not built) · **Depth:** full execution · **"A management surface, off the paste loop."**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-8](STAGE-8-pinning.md)
Canonical: [PRD](../PRD.md) · [DESIGN](../DESIGN.md) · [FEATURES](../FEATURES.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

A real home for a growing library: a normal, resizable, focus-taking `NSWindow` with three panes —
**folder sidebar | prompt list | detail editor**. It opens from the menu bar, lets you browse,
search, create, edit, organize into folders, and pin prompts to ⌥1–9. Its detail pane **retires the
modal `PromptEditorPanel`** (the Stage-2-era editor) entirely — there is now one editing surface, and
it lives inside the Library.

**The feeling it protects** — Principle 4, *the library must fill itself*
([PRD §6](../PRD.md#6-principles)): as the catalog grows past a handful of prompts, hand-editing
markdown and a one-shot modal stop scaling. The Library makes organizing painless without ever
touching the fast path.

### The load-bearing invariant: the Library is off the paste loop

This window is a normal **activating** `NSWindow` — it takes focus like any Mac app window. That is
safe, and *only* safe, because it **never participates in the paste loop**:

- It **never calls `Capture`** (no frontmost-app snapshot, no selection read).
- It **never calls `panelController.present()`** — it is not the ⌥Space palette.
- It **never calls `PasteService`** — it writes `.md` files through `PromptStore`, nothing else.

Because it never pastes into another app, the whole "never steal focus / capture-before-show /
~700ms" contract that governs the palette **does not apply to it**. This is the deliberate, accepted
amendment to the PRD §7 "no settings/preferences window" non-goal: a *management* window is now in
scope, justified precisely by this off-paste-path property. **Keep this invariant prominent in the
code** (a file-header comment on `LibraryWindowController.swift`) — it is the entire reason the
non-goal could be relaxed. If a future change ever makes this window call `Capture`/`present()`/
`PasteService`, the amendment is void and the design is broken.

This is distinct from the **pinning-vs-adaptive-HUD** collision resolved in [STAGE-8](STAGE-8-pinning.md)
(hybrid: pins claim their ⌥-number first, frecency fills the gaps). Stage 8 settled *how pins behave*;
Stage 9 gives the user the surface to *set* them.

## 2. Entry gate

[STAGE-8](STAGE-8-pinning.md) shipped: the data model carries `folder`, `pinnedSlot`, and
`description`; `PromptStore` scans recursively, watches via FSEvents, exposes `resolvePins` /
`pinnedAssignment()` / `onReload`; and the palette shows pinned chips. The Library window is the
management surface over that model — build it once a flat menu + modal editor stops scaling for a
multi-folder, partly-pinned library.

## 3. Features in this stage

- A three-pane `NSWindow` (sidebar | list | detail) opened from the menu bar; resizable, activating,
  **off the paste loop**.
- **Sidebar** scopes: `all` / `pinned` / `recent` (with counts) + a `folders` section (one row per
  real subdirectory, each with a count) + `+ new folder`.
- **Middle list**: a `Filter…` field + table, scoped to the sidebar selection; two-line cells
  (title + description).
- **Detail pane** (the new editor, replacing `PromptEditorPanel`): title, folder picker, pin toggle +
  editable hotkey, description, body, a usage line, delete.
- **Folder move** via a new `PromptStore.move(_:toFolder:)` that migrates the frecency usage key.
- **Pin/hotkey conflicts** resolve by a **user-initiated steal** (clear the prior holder's `pin:`,
  rewrite that file, warn inline).
- **Live refresh** off `promptStore.onReload`, guarded against clobbering an in-progress edit.
- Menu-bar `Library…` and `New Prompt…` entries; `onEdit` and ⌥⇧Space inverse-capture route here;
  `PromptEditorPanel.swift` is deleted.

## 4. UX

The canonical mockup lives in [FEATURES](../FEATURES.md) (the three-pane window). Described here so the
implementation matches it:

```
┌──────────────┬───────────────────────────┬──────────────────────────────────┐
│  all      7  │  Filter…                  │  Bug report template             │
│  pinned   3  │ ┌───────────────────────┐ │  Folder  [ Engineering    ▾ ]    │
│  recent      │ │ Bug report template   │ │  Pin  (●—)  ⌥[ 3 ]               │
│              │ │ Structured repro…     │ │  Description                     │
│  folders     │ ├───────────────────────┤ │  [ Structured repro steps…    ] │
│  Engineering3│ │ PR description        │ │  Body                           │
│  Comms     2 │ │ Summarize the diff…   │ │  ┌────────────────────────────┐ │
│  Writing   2 │ ├───────────────────────┤ │  │ ## Steps to reproduce      │ │
│              │ │ Standup update        │ │  │ 1. …                       │ │
│  + new folder│ │ What I shipped…       │ │  │                            │ │
│              │ └───────────────────────┘ │  └────────────────────────────┘ │
│              │                           │  used 42× · last used 2h ago     │
│              │                           │              [ delete ]          │
└──────────────┴───────────────────────────┴──────────────────────────────────┘
```

- **Left — sidebar.** `all` (count = all prompts), `pinned` (count = prompts with `pinnedSlot != nil`),
  `recent` (top-N by frecency). A `folders` header, then one row per real subdirectory of `~/Prompts`
  with its prompt count. `+ new folder` at the bottom creates an empty subdirectory and selects it.
  Selecting a row sets the active `LibraryScope` and drives the middle list. The sidebar **cannot
  collapse**.
- **Middle — list.** A `Filter…` field on top; below it a table of two-line cells (title in
  `Palette.primary`, description in `Palette.secondary`/`footer`). The list is
  `promptStore.filter(query)` narrowed to the active scope. Selecting a row loads it into the detail
  pane. Empty filter shows the scope's full set in frecency order.
- **Right — detail.** The editor:
  - **Title** field (the frontmatter `name`).
  - **Folder** picker (`NSPopUpButton`): every existing folder + root + a "New folder…" item.
  - **Pin** toggle (`NSSwitch`) + an editable **⌥-hotkey** field (1–9). Off = unpinned; on with a
    number claims that slot.
  - **Description** single-line field.
  - **Body** (`NSTextView` in a scroll view).
  - A **usage line**: `used 42× · last used 2h ago`.
  - A red **delete** button (with a confirm step).
- Same Mattmode-Mono dark surface as the palette ([FEATURES §0](../FEATURES.md#0-visual-system--mattmode-mono)),
  via the shared `Palette` (see §5).

## 5. Design / mechanism

### 5.1 Extract the palette — `Promptly/Palette.swift` (new)

The `Palette` enum (dark colors + JetBrains Mono font helpers) is currently `private` in
`Promptly/PanelController.swift:5–23`. Lift it **verbatim** into a new shared
`Promptly/Palette.swift` (drop `private` so both files can see it) so the palette and the Library
window agree on **one** definition (and so the new window doesn't fork the ad-hoc color constants that
`PromptEditorPanel.swift:13–20` carried).

- **Scope of the extraction:** move only the `Palette` enum. **Do not touch anything else in
  `PanelController.swift`** — not the row layout, not the pin-chip styling, not ask-mode, not the
  resize/height math. PanelController keeps working against the same `Palette.*` symbols; it just no
  longer owns the definition.

### 5.2 The window — `Promptly/LibraryWindowController.swift` (new)

A normal activating, titled, resizable `NSWindow` driven by an `NSWindowController` (or an
`NSObject` controller owning the window). **File-header comment must state the off-paste-path
invariant from §1.**

Use **`NSSplitViewController`** with three `NSSplitViewItem`s. Set explicit per-pane
`minimumThickness`/`maximumThickness` and `holdingPriority` so a pane can't collapse to zero width
(the classic split-view bug):

- **Sidebar item:** `minimumThickness ≈ 180`, `canCollapse = false`, highest holding priority (stays
  put when the window resizes).
- **List item:** a sensible min (≈ 220), **lowest** holding priority so it absorbs window-resize
  slack and flexes.
- **Detail item:** a min (≈ 320) wide enough for the body editor; mid holding priority.

**Sidebar** — `NSOutlineView` (or a sectioned `NSTableView`): the three scope rows, a `folders`
header, folder rows, `+ new folder`. Each row carries a count. Selection emits a `LibraryScope`
(§5.4). Folder rows derive from the distinct non-empty `folder` values across
`promptStore.prompts` (plus any empty folders the user just created).

**List** — `Filter…` `NSTextField` + `NSTableView`. On every keystroke and on scope change, recompute
`LibraryScope.filter(prompts: promptStore.prompts, query:)` (§5.4) and reload. Two-line cells.

**Detail** — the editor. **Lift the `NSTextView`-in-scroll-view setup** for the body verbatim from
`PromptEditorPanel.swift:113–141` (the scroll view, container sizing, `widthTracksTextView`, colors,
insertion point) — that geometry is already correct; reuse it rather than re-deriving it. Add the new
fields the old modal lacked: **folder picker**, **pin toggle + hotkey**, **description**, and the
**usage line**. Everything styled through `Palette`.

### 5.3 `PromptStore.move(_:toFolder:)` (new method — Stage 9 work)

`PromptStore` does **not** have a move method yet — add it. It renames a prompt's file from its
current folder to a target folder **and migrates its frecency usage key**, because `filename` is the
usage-dict key (`PromptStore.swift:9`, used at `:147–152`). Without the migration, a reorganize would
silently reset the prompt's `used N×` history — the exact risk the relative-`filename` design called
out.

Build it on the existing mechanics:

- Compute the new relative path the way `newSlug(for:in:)` (`PromptStore.swift:269–284`) scopes
  uniqueness **to the target folder** — so moving `foo.md` into `Engineering/` where a `foo.md`
  already lives lands as `Engineering/foo-2.md`, not a clobber.
- `createDirectory(withIntermediateDirectories: true)` for the destination (as `save` does at
  `:199–200`), then `FileManager.moveItem(at:to:)`.
- **Migrate usage:** `usage[new] = usage[old]; usage.removeValue(forKey: old)` then `persistUsage()`
  (mirrors how `delete` maintains the dict at `:224–225`).
- Set `suppressReloadUntil` and call `load()` — same self-write-suppression pattern as `save`
  (`:204–205`) so the FSEvents callback doesn't double-reload.

Signature, e.g.: `func move(_ prompt: Prompt, toFolder folder: String)`.

### 5.4 `LibraryScope` (new, pure — the Tier-A seam)

```swift
enum LibraryScope: Equatable {
    case all
    case pinned
    case recent
    case folder(String)
}
```

Filtering is a **pure** static function with no `NSView` dependency, so Tier A can test it directly:

```swift
extension LibraryScope {
    /// Scope first, then the filter text composes on top.
    static func filter(_ scope: LibraryScope,
                       prompts: [Prompt],
                       usage: [String: PromptUsage],
                       query: String,
                       now: Date = Date()) -> [Prompt]
}
```

- `all` → every prompt.
- `pinned` → `pinnedSlot != nil`, ordered by slot ascending.
- `recent` → frecency top-N (reuse `PromptStore.rank(_:usage:now:)`).
- `folder("X")` → prompts whose `folder == "X"`.
- A non-empty `query` then composes on top (same fuzzy match `PromptStore.filter` uses). The window
  may call `promptStore.filter(query)` for the live UI and intersect with the scoped set, but the
  **pure `LibraryScope.filter` is the source of truth and the thing Tier A asserts**, so keep the
  scope logic in it (not buried in a view).

> Implementation note: pass `usage` in (rather than reaching into the store) to keep the function
> pure and testable. Expose `PromptStore.rank` / the usage dict to the window as needed — without
> mutating the existing frecency code.

### 5.5 Behavior wiring (all mutations go through `PromptStore`)

`PromptStore` already writes files and reloads on every mutation, then fires `onReload`. The window
drives it and reacts to that hook.

- **Create** → `promptStore.save(name:keywords:body:folder:pinnedSlot:description:filename:)` with
  `filename: ""` (the store mints a folder-scoped slug). Folder comes from the detail's picker.
- **Edit** → the same `save(...)` with the existing `filename` (the extended signature already exists
  at `PromptStore.swift:194–206`, carrying `folder`/`pinnedSlot`/`description`).
- **Delete** → confirm, then `promptStore.delete(_:)` (`PromptStore.swift:221–227`). The old modal had
  no delete; the confirm dialog is **new UI** in the detail pane (a standard `NSAlert`
  destructive-style confirm before calling `delete`).
- **Move folder** → `promptStore.move(_:toFolder:)` (§5.3). Triggered when the detail's folder picker
  changes for an existing prompt (vs. a plain re-`save`, which would orphan the old file and lose the
  usage key).
- **Pin / hotkey (the user-initiated steal):** turning the toggle on with number *N* claims slot *N*.
  If another prompt already holds *N*, **steal it**:
  1. Clear the previous holder's `pin:` and rewrite that file via `save(...)` with `pinnedSlot: nil`.
  2. Save this prompt with `pinnedSlot: N`.
  3. Show an **inline warning** in the detail pane: `⌥3 was on 'X' — moved here`.

  This is **deliberately destructive and user-initiated** — distinct from Stage 8's *silent,
  non-destructive* load-time conflict handling (`resolvePins` leaves the loser's file untouched and
  just reports a `PinConflict`, `PromptStore.swift:341–353`). At load we never rewrite; here the user
  explicitly asked to take the slot, so we do rewrite — and tell them.
- **Live refresh:** subscribe to `promptStore.onReload` (`PromptStore.swift:63`, present but unused
  until now). On reload, refresh sidebar counts, the list, and the detail's read-only bits (usage
  line). **Guard:** do **not** overwrite the detail's editable fields (title/description/body) while
  one of them is the window's `firstResponder` — an external FSEvents reload mid-edit must not clobber
  what the user is typing. (Refresh the list/sidebar regardless; only the in-edit detail fields are
  protected.)

### 5.6 `Promptly/main.swift` — retire the modal, route everything to the window

Retire `PromptEditorPanel` and `openEditor`; the Library window is the only editor. Concretely:

- **Remove** `var editorPanel: PromptEditorPanel?` (`main.swift:10`) and the whole
  `openEditor(editing:initialBody:)` method (`main.swift:130–139`). Add a single
  `var libraryWindow: LibraryWindowController?` (lazily created, reused).
- `buildMenu()` (`main.swift:97`): keep `Open prompts folder…`. Replace the lone `New Prompt…`
  (`main.swift:105`) with **two** items:
  - **`Library…`** → open the window, select the `all` scope, focus the filter field.
  - **`New Prompt…`** → open the window on a **blank detail** (new, unsaved prompt; root folder).
- `panelController.onEdit` (`main.swift:27`): instead of `openEditor(editing: prompt)`, open the
  window **focused on that prompt** (select it in the list, load it in the detail).
- ⌥⇧Space inverse-capture (`onCaptureHotkey`, `main.swift:53–61`): instead of
  `openEditor(editing: nil, initialBody: selection)`, open the window on a **blank detail pre-filled
  with the captured selection as the body** (folder = root, title empty and focused). The selection is
  still read *before* the window shows (it reads from the host app while that app is frontmost — the
  capture itself is unchanged; only the destination surface changes).

### 5.7 `run.sh` — build manifest

`run.sh` lists every app `.swift` in `swiftc` order, app files before `main.swift`
(`run.sh:20–29`). For Stage 9:

- **Remove** `"$PROJECT_ROOT/Promptly/PromptEditorPanel.swift"` (`run.sh:27`).
- **Add** `"$PROJECT_ROOT/Promptly/Palette.swift"` and `"$PROJECT_ROOT/Promptly/LibraryWindowController.swift"`,
  both **before** `main.swift`, following the existing ordering convention (Palette early, since both
  PanelController and the window depend on it).

Test files are **not** added to `run.sh` — each carries its own standalone `swiftc` line in a header
comment (the `HudAssignTests.swift` convention).

## 6. Tests for this stage

### Tier A — autonomous (an agent runs these)

- **`LibraryScopeTests.swift` (new):** pure, **no `NSView`**. Drive `LibraryScope.filter` over a fixed
  array of `Prompt` + a synthetic `usage` dict:
  - `all` returns the full set.
  - `pinned` returns only `pinnedSlot != nil`, ordered by slot.
  - `recent` returns frecency top-N (matches `PromptStore.rank` order).
  - `folder("Engineering")` returns exactly that folder's prompts; `folder("")` returns root prompts.
  - A non-empty `query` composes with the scope (scope-then-fuzzy), e.g. `pinned` + `"bug"` narrows
    within the pinned set.
- **`PromptStoreTests.swift` (extend further):** over a temp `~/Prompts`:
  - `move(_:toFolder:)` **rewrites the relative filename** (root `foo.md` → `Engineering/foo.md`) and
    the file lands in the new directory.
  - `move(_:toFolder:)` **migrates the usage key**: after recording use on `foo.md` then moving it,
    the `used N×` history is keyed under the new path and the old key is gone.
  - **Per-folder slug uniqueness on move**: moving `foo.md` into a folder that already has `foo.md`
    yields `foo-2.md`, not a clobber.

Keep these green; never weaken an assertion to pass (CLAUDE.md honesty rules). A move that loses the
usage key, or a slug collision that clobbers a file, is a **real bug** to fix, not a test to soften.

### Tier B — human-in-the-loop (agent prepares, author runs)

Window rendering, focus, and split-pane behavior need a **real window server and human eyes** — an
agent can neither lay out an `NSSplitViewController` on screen nor judge focus/refresh timing. As the
project's Tier A/B boundary states (CLAUDE.md), the agent **keeps Tier A green and writes out these
steps; it cannot run them.** Author runs after `./run.sh`:

1. **Open & layout:** menu bar → `Library…`. Sidebar shows `all`/`pinned`/`recent` with correct
   counts and `folders` with per-folder counts. Drag the split dividers to the edges — **no pane
   collapses to zero**; sidebar holds ~180 min.
2. **Filter + scope:** select `pinned`; the list shows only pinned prompts. Type in `Filter…`; results
   narrow within the scope. Switch to a folder; list reflects it.
3. **Edit + save:** open a prompt, change the body, Save → confirm the `.md` on disk updated; the
   palette (⌥Space) reflects it.
4. **Live refresh while editing:** with the detail focused mid-edit, externally `touch`/edit a
   *different* `.md` in `~/Prompts` → the list/sidebar refresh, but **your in-progress edit is not
   clobbered**.
5. **Pin steal:** pin a prompt to a number another prompt already holds → the inline warning shows
   (`⌥N was on 'X' — moved here`), the previous file's `pin:` is cleared on disk, and ⌥Space shows the
   new holder.
6. **Move folder:** move a prompt between folders via the picker → the file moved on disk **and** its
   `used N×` history survived (frecency intact).
7. **Delete:** delete with the confirm step → file removed, list updates.
8. **Off-paste-path proof:** with the Library window focused, ⌥Space still pastes into the *previous*
   frontmost app — the window taking focus does **not** affect the paste loop.

## 7. Build checklist

Canonical (once added): [TASKS Stage 9](../TASKS.md#stage-9--three-pane-library-window).

- [ ] Extract `Palette` from `PanelController.swift` into a shared `Promptly/Palette.swift` (verbatim;
      drop `private`; touch nothing else in PanelController).
- [ ] `Promptly/LibraryWindowController.swift`: activating, resizable `NSWindow` via
      `NSSplitViewController`; **file-header comment states the off-paste-path invariant** (never
      `Capture`/`present()`/`PasteService`).
- [ ] Per-pane min/max + holding priority; sidebar `minimumThickness ~180`, `canCollapse = false`;
      list lowest holding priority.
- [ ] Sidebar: `all`/`pinned`/`recent` with counts, `folders` section with per-folder counts,
      `+ new folder`.
- [ ] Middle list: `Filter…` field + two-line cells, scoped via `LibraryScope.filter`.
- [ ] Detail pane: title, folder picker, pin toggle + editable ⌥-hotkey, description, body
      (lift the `NSTextView`/scroll setup from `PromptEditorPanel.swift:113–141`), `used N× · last
      used …` line, red delete with confirm.
- [ ] `LibraryScope` enum + pure `LibraryScope.filter(...)`.
- [ ] `PromptStore.move(_:toFolder:)`: rename across folders (folder-scoped slug uniqueness) +
      migrate the usage key + suppress-reload + `load()`.
- [ ] Wire create/edit/delete → `PromptStore`; move → `move(_:toFolder:)`; pin/hotkey conflict →
      **user-initiated steal** (clear prior holder's `pin:`, rewrite, inline warning).
- [ ] Subscribe to `promptStore.onReload`; refresh sidebar/list/usage-line; **guard** detail fields
      while a text field is first responder.
- [ ] `main.swift`: remove `editorPanel` + `openEditor`; add `Library…` + `New Prompt…` menu items;
      route `onEdit` and ⌥⇧Space inverse-capture to the window; reuse one `libraryWindow`.
- [ ] `run.sh`: add `Palette.swift` + `LibraryWindowController.swift` before `main.swift`; **remove
      `PromptEditorPanel.swift`**.
- [ ] Delete `Promptly/PromptEditorPanel.swift`.
- [ ] `LibraryScopeTests.swift` (new) + `PromptStoreTests.swift` (move + usage-key migration + slug
      uniqueness) green; typecheck gate green.

## 8. Exit criterion

> You open the Library from the menu bar and manage a real, growing catalog there — browse by
> folder/scope, search, create/edit/delete, set pins, and reorganize into folders — and the file on
> disk always matches what you did, with `used N×` history surviving a folder move and a pin steal
> warning when you take an occupied ⌥-number. The modal `PromptEditorPanel` is gone; this is the one
> editor. And because the window never pastes — it never calls `Capture`, `present()`, or
> `PasteService` — it can take focus freely without ever touching the ⌥Space paste loop or the
> ~700ms feel.
