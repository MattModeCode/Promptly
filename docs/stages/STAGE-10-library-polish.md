# Stage 10 — Library polish / folder management

**Status:** Pre-scaffold · **Depth:** tiered · **"The library you can keep tidy."**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-9](STAGE-9-library-window.md)
Canonical: [FEATURES](../FEATURES.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

Stage 9 gave the user a three-pane Library window (folder sidebar | prompt list | detail
editor) that browses, searches, creates, edits, and pins — but it can only *use* the folders
that already exist on disk and it stays silent about pin conflicts. Stage 10 is the **polish
pass** that makes the library feel *maintainable from inside the app*: create and rename
folders, drag a prompt between folders, don't leave phantom empty folders cluttering the
sidebar, surface the pin conflict that Stage 8 already resolves silently, and render the raw
`used 42× · lastUsed 2026-06-18T…` data as a human "last used 2h ago" line.

**The feeling it protects:** the library never *fights* the user — reorganizing is direct
(drag, rename), nothing silently breaks (a pin steal/conflict is always explained), and the
usage line reads like a sentence, not a timestamp.

This is explicitly the *polish* stage. It adds **no new top-level feature** — every item here
sharpens a surface Stage 9 already built. Don't invent more.

## 2. Entry gate

[STAGE-9](STAGE-9-library-window.md)'s Library window must already exist and work: the
`NSSplitViewController` with all three panes (sidebar scopes + folder rows, the filterable
middle list, the detail editor), wired through `PromptStore`'s `save`/`delete`/`move` +
`onReload`. Stage 10 only edits `LibraryWindowController.swift` (and adds one pure helper file);
**none of this polish makes sense until the window itself is real.** In particular it depends on:

- `PromptStore.move(_:toFolder:)` (Stage 9) — drag-to-move reuses it verbatim; folder-rename
  reuses its usage-key-migration *pattern* applied to a whole folder at once.
- `PromptStore.resolvePins(_:) -> (pins, conflicts)` (Stage 8, shipped) — the inline conflict
  banner renders the `[PinConflict]` it already returns; this stage adds **no** new resolution
  logic, only UI.
- `LibraryScope` + the sidebar folder rows (Stage 9) — rename/create/empty-cleanup all act on
  the folder list the sidebar already derives.

## 3. Features in this stage

Five items, all inside the Stage 9 Library window:

1. **Folder create / rename.** Create an empty folder from the sidebar; rename an existing one.
   Rename **rewrites every prompt file's relative path** under that folder *and* **migrates each
   affected prompt's usage-dict key** (the Stage 9 `move` pattern, applied folder-wide).
2. **Drag-to-move.** Drag a prompt row from the middle list onto a sidebar folder row to move it
   into that folder (reuses `PromptStore.move(_:toFolder:)`).
3. **Empty-folder cleanup.** When a folder's last prompt leaves (moved or deleted), the
   zero-count folder must not linger as a phantom sidebar row.
4. **Inline pin-conflict warning UI.** Surface the `PinConflict` values from
   `PromptStore.resolvePins` inside the window (Stage 8 resolves them deterministically and
   non-destructively but shows the user *nothing*).
5. **Relative-time formatting.** A new pure helper turns a raw `lastUsed` `Date` into "just now"
   / "5m ago" / "2h ago" / "yesterday" / weekday / date, for the detail pane's
   `used 42× · last used 2h ago` line.

## 4. UX

- **Create folder:** the sidebar's `+ new folder` affordance (Stage 9) prompts for a name and
  adds an (initially empty) folder row, selectable as a `LibraryScope.folder(name)`.
- **Rename folder:** double-click a sidebar folder row (or a context-menu "Rename") makes the
  label editable; commit rewrites the on-disk subdirectory and all child paths. The detail pane,
  if it was showing a prompt now living under the new path, keeps showing the same prompt (its
  `filename` updated) — usage history (`used N×`) survives because the key migrated.
- **Drag-to-move:** pick up a middle-list row; sidebar folder rows highlight as valid drop
  targets; dropping moves the file and the row leaves the current list if the move changed its
  scope. Dragging onto the `all` scope or its own current folder is a no-op.
- **Empty-folder cleanup:** moving/deleting the last prompt out of a folder makes that folder's
  sidebar row disappear on the next reload (it no longer has a count to show). See §5 for the
  exact rule — disk state is intentionally left alone; only the *sidebar* hides 0-count folders.
- **Pin-conflict banner:** when two files declare the same `pin:`, the loser is unpinned for
  assignment (Stage 8). Stage 10 shows an inline warning near the affected slot — e.g. a small
  amber banner in the detail pane of the *loser* ("⌥3 is already on 'Bug report' — this prompt
  is unpinned") and/or a marker on the contested row in the list. It's informational, not a
  blocking modal; it clears when the conflict is resolved (the user re-pins to a free slot).
- **Relative-time line:** `used 42× · last used 2h ago` — the count is literal, the time is the
  `RelativeTime.format` output. "Never used" when count is 0.

> Visual reference: this stage realizes the three-pane window mockup in
> [FEATURES](../FEATURES.md) at full polish — the folder sidebar is now editable, not read-only.

## 5. Design / mechanism

All changes live in `Promptly/LibraryWindowController.swift` plus one new **pure** file. Nothing
touches the paste loop, the panel, the hotkey, or any height/freeze math — the window is off the
paste path (the Stage 9 safety invariant), so this is all ordinary AppKit + `PromptStore` work.

### 5.1 Folder rename — path rewrite + usage-key migration (pure-extractable)

Renaming folder `Old` → `New` must, for **every** prompt whose `folder == "Old"` (or is nested
under it, i.e. `filename` has prefix `"Old/"`):

- rewrite its relative `filename`: `"Old/foo.md"` → `"New/foo.md"` (preserving any deeper
  nesting `"Old/sub/foo.md"` → `"New/sub/foo.md"`);
- move the file on disk to the new path (`withIntermediateDirectories: true`);
- **migrate the usage key** `usage["Old/foo.md"] → usage["New/foo.md"]` so `used N×` / frecency
  survive — exactly the migration `PromptStore.move(_:toFolder:)` does for one file, done here
  for the whole set.

Add `PromptStore.renameFolder(_ old: String, to new: String)` doing the on-disk + usage-key work
(it's the loop over `move`'s logic). Keep the **path-rewrite arithmetic pure and Tier-A
testable** — factor the string transform into a pure static like
`static func rewriteFolderPath(_ filename: String, from old: String, to new: String) -> String`
so the rename can be asserted without the filesystem. Per-folder slug uniqueness (Stage 8/9)
still holds: if `New` already exists, either merge with collision-safe slugs or reject the
rename — pick the simpler rule and document it in the method doc-comment; don't silently
overwrite a same-named file in the destination.

### 5.2 Drag-to-move (Tier B — AppKit drag session)

Make the middle `NSTableView` a drag source (`pasteboardWriter` carrying the row's `filename`)
and the sidebar folder rows a drop destination (`validateDrop` accepts a folder row,
`acceptDrop` calls `promptStore.move(prompt, toFolder: targetFolder)`). The move itself is the
already-tested Stage 9 path; only the drag *plumbing* is new, and it's inherently Tier B (needs
a real window server + a human dragging). No new pure logic here.

### 5.3 Empty-folder cleanup — design decision (documented rule)

**Rule:** the sidebar derives its folder rows from the *prompts currently loaded*. A folder row
is shown only if at least one loaded prompt has that `folder`. So when the last prompt leaves a
folder, the folder simply **drops off the sidebar at the next `onReload`** — no count, no row.
The underlying now-empty directory on disk is **left in place**: directories are not config and
carry no state, an empty dir is harmless, and actively `rmdir`-ing on every move risks deleting a
folder the user just created-and-not-yet-filled or is mid-reorganize. This keeps the rule a pure
derive-from-loaded-prompts computation (no disk mutation, easy to reason about) at the cost of a
stale empty dir the user can delete in Finder if they care.

> Edge case this rule handles for free: a folder the user *creates* but hasn't put a prompt in
> yet has no loaded prompt, so by the strict rule it wouldn't appear. Stage 10's create-folder
> therefore tracks **freshly-created-but-empty** folders in an in-memory set on the controller so
> a just-made folder stays visible until the window closes (or the user moves a prompt into it);
> it is *not* persisted, matching "empty dirs carry no state." Document this so the create + the
> cleanup rules don't appear to contradict.

### 5.4 Inline pin-conflict UI

On each `onReload`, the controller already has `promptStore` — call `resolvePins(prompts)` (or a
thin `promptStore.pinConflicts()` wrapper over it) to get `[PinConflict]`. Index them by
`loser` filename. When the detail pane shows a prompt that is a conflict `loser`, render the
inline amber banner (built from the `PinConflict.slot` + the `winner`'s title, looked up by
filename). Optionally flag the contested rows in the middle list. This is **render-only** —
resolution stays in Stage 8's pure `resolvePins`; Stage 10 adds no new conflict math.

### 5.5 Relative-time helper (pure, Tier-A)

Add `Promptly/RelativeTime.swift` with one pure entry point:

```swift
enum RelativeTime {
    /// Human relative string for `date` as seen at `now` (injectable for tests).
    static func format(_ date: Date, now: Date = Date()) -> String
}
```

Bucket boundaries (assert each in tests):

| elapsed (`now - date`)            | output            |
|-----------------------------------|-------------------|
| `< 60s`                           | `just now`        |
| `< 60m`                           | `Nm ago`          |
| `< 24h`                           | `Nh ago`          |
| same prior calendar day (`< 48h`) | `yesterday`       |
| `< 7d`                            | weekday (`Tuesday`)|
| `>= 7d`                           | short date (`Jun 12`) |

Keep it pure and `now`-injectable so the test pins a fixed `now` and walks each boundary. The
detail pane composes `"used \(count)× · last used \(RelativeTime.format(lastUsed))"`, or
`"never used"` when `count == 0`.

## 6. Tests for this stage

### Tier A — autonomous (agent runs)

- **`RelativeTimeTests.swift` (new, pure):** fix a `now` timestamp and assert each bucket and
  each boundary — `now-30s` → "just now", `now-90s` → "1m ago", `now-2h` → "2h ago",
  `now-(yesterday)` → "yesterday", `now-3d` → that weekday, `now-10d` → short date. No `NSView`,
  no FS. Standalone `swiftc` line in the file header (the `HudAssignTests` convention), **not**
  added to `run.sh`.
- **`PromptStoreTests.swift` (extend):** folder-rename path-rewrite + usage-key migration —
  assert `rewriteFolderPath("Old/foo.md", from: "Old", to: "New") == "New/foo.md"` (and the
  nested case); assert `renameFolder` migrates `usage["Old/foo.md"] → usage["New/foo.md"]` and
  leaves unrelated keys untouched. Mirror the `move(_:toFolder:)` test pattern Stage 9 establishes.
- **Typecheck gate:** `arch -x86_64 swiftc -typecheck` over the sources stays green.

Keep the honesty rules: never weaken an assertion to go green; the rename test asserting a *lost*
usage key is a real bug to fix in `renameFolder`, not in the test.

### Tier B — human-in-the-loop (agent prepares, author runs)

An agent **cannot** verify any of these (they need a real window server + a human dragging and
looking); the agent's job is to keep Tier A green and lay out these steps:

1. **Rename folder:** rename `Engineering` → `Eng` in the sidebar; confirm every prompt moved on
   disk to `~/Prompts/Eng/…`, the sidebar row relabeled, and a renamed prompt's `used N×` line
   is unchanged (history survived the key migration).
2. **Drag-to-move:** drag a prompt from the middle list onto another sidebar folder; confirm the
   file moved on disk and the row left the old folder's list; confirm `used N×` survived.
3. **Empty-folder cleanup:** move the last prompt out of a folder; confirm the now-empty folder's
   row disappears from the sidebar on reload; confirm a *freshly created* empty folder still shows
   until you act on it.
4. **Pin-conflict banner:** give two prompts the same `pin: 3`; open the loser in the detail pane;
   confirm the inline amber warning naming ⌥3 and the winning prompt; re-pin the loser to a free
   slot and confirm the banner clears.
5. **Relative-time line:** confirm the detail pane reads "used N× · last used 2h ago"-style text
   that updates sensibly as a prompt is used.

## 7. Build checklist

Canonical: [TASKS Stage 10](../TASKS.md#stage-10--library-polish--folder-management).

- [ ] `PromptStore.renameFolder(_:to:)` — rewrites every child file's relative path on disk and
      migrates each affected `usage` key (whole-folder application of the `move` pattern).
- [ ] `PromptStore.rewriteFolderPath(_:from:to:)` — pure static string transform (root of the
      rename logic), Tier-A testable without the filesystem.
- [ ] Sidebar **create folder** (with the in-memory freshly-created-empty set so a new empty
      folder stays visible) and **rename folder** (double-click / context menu) UI in
      `LibraryWindowController.swift`.
- [ ] **Drag-to-move:** middle-list rows as drag source, sidebar folder rows as drop target,
      `acceptDrop` → `promptStore.move(_:toFolder:)`. No-op on `all`/same-folder drops.
- [ ] **Empty-folder cleanup:** sidebar shows a folder row only if a loaded prompt has that
      folder (plus the freshly-created-empty set); no disk deletion. Documented as a design rule.
- [ ] **Inline pin-conflict UI:** index `resolvePins(prompts).conflicts` by `loser`; render the
      amber banner in the detail pane for a conflict-loser prompt. Render-only; no new resolution.
- [ ] `Promptly/RelativeTime.swift` — pure `RelativeTime.format(_:now:)`; detail pane uses it for
      the `used N× · last used …` line ("never used" when count 0).
- [ ] `run.sh`: add `RelativeTime.swift` to the `swiftc` source list (before `main.swift`).
      `RelativeTimeTests.swift` keeps its own standalone `swiftc` line in a header comment — not
      added to `run.sh`.
- [ ] **Tier A green:** `RelativeTimeTests`, the extended `PromptStoreTests` (rename + path
      rewrite), and the typecheck gate all pass.

## 8. Exit criterion

> The library is maintainable entirely from inside the window: folders can be created and
> renamed (with usage history surviving the rename), prompts can be dragged between folders,
> emptied folders quietly drop off the sidebar, a pin conflict is always explained inline, and
> the usage line reads as a human "last used 2h ago" — all without ever touching the ⌥Space
> paste loop or the half-second feel.

Tier A (relative-time buckets, folder-rename path rewrite + usage-key migration, typecheck) is
green; the drag/drop, empty-folder disappearance, pin-conflict banner, and rename UI are Tier B,
confirmed by the author per the steps in §6.
