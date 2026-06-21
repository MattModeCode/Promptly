# HUD-select hotkey: swap ⌥1–9 for ⌘1–9

## Problem

Stage 7's adaptive HUD row binds firing a frozen slot to ⌥1–9 (`Promptly/PanelController.swift`,
`FilterField.performKeyEquivalent`). Option+digit is a macOS-reserved combo for inserting special
characters (¡™£¢∞§¶•ªº on a US keyboard), and the author hit a real conflict with it. The fix is to
rebind HUD-select to a chord macOS doesn't already claim for digit keys.

## Scope

This shortcut is local, not global: it's intercepted inside `FilterField.performKeyEquivalent`,
which only fires while the palette's filter field is the first responder in the key window. It is
unrelated to the Carbon-registered global ⌥Space / ⌥⇧Space hotkeys in `HotkeyManager.swift`, which
are untouched by this change.

## Decision

Rebind HUD-select from ⌥1–9 to ⌘1–9.

- ⌘+digit is not reserved by macOS for character insertion.
- The existing Cmd+E ("edit") interception in the same method establishes precedent for a bare-Cmd
  chord living in this field; ⌘1–9 sits alongside it without collision (E is not a digit).
- Trade-off accepted: some host apps bind ⌘1–9 to their own tab/window switching (e.g. browser tab
  selection). This is a non-issue here because the chord is only intercepted while the *palette's*
  field has key focus, not the host app's — the host app's own ⌘1–9 binding is irrelevant while the
  palette is frontmost-for-input.

## Changes

1. **Behavior** — `PanelController.swift`, `FilterField.performKeyEquivalent`: change the modifier
   guard from `.option` to `.command` for the digit-fire branch. Keep the existing exclusivity
   pattern (require Command, exclude Shift to avoid colliding with shifted-symbol chords), mirroring
   how the neighboring Cmd+E branch is guarded.
2. **Display glyph** — `PanelController.swift`: the two HUD-chip render sites currently producing
   `"⌥\(n)"` (the resting top-9 row chip, and the hotkey badge in the detail/library row) change to
   `"⌘\(n)"`.
3. **Conflict toast** — `LibraryWindowController.swift` (~line 665): the hotkey-collision message
   `"⌥\(hotkey) was on '\(conflict.name)' — moved here"` changes its glyph to `⌘`.
4. **Comments** — every comment in `PanelController.swift` and `PromptStore.swift` referencing
   ⌥1–9 / ⌥-number / ⌥N as the HUD-select mechanism updates its glyph to ⌘, since these comments
   document live behavior (this repo treats them as load-bearing, not decorative).
5. **Stage doc** — `docs/stages/STAGE-7-adaptive-hud-row.md`: update ⌥-number references to ⌘ so
   the spec matches shipped behavior.

## Out of scope

- No change to the global ⌥Space / ⌥⇧Space Carbon hotkeys.
- No change to how hotkey numbers are assigned, stored in frontmatter, or resolved on conflict —
  only the trigger modifier and its displayed glyph change.
- No settings/preference to make the modifier user-configurable — out of scope for this fix.

## Testing

Mechanical rename with no new control flow — verify with:

- `arch -x86_64 swiftc -typecheck` (or full `./run.sh` build) to confirm no stale ⌥-branch logic
  remains and the project still compiles.
- Manual smoke check (Tier B, author): open the palette, confirm ⌘1–9 fires the corresponding HUD
  slot, and confirm bare digit keys (no modifier) still type into the filter field normally.
