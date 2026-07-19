# DESIGN — Technical Design

**Status:** Stages 0–10 code-complete · **Stack:** native Swift / AppKit · **Arch:** native Apple Silicon (arm64) by default; Universal (arm64+x86_64) on release
Sibling docs: [PRD.md](PRD.md) · [FEATURES.md](FEATURES.md) · [TASKS.md](TASKS.md) · [FEATURE-CATALOG.md](FEATURE-CATALOG.md)

Seeded from the office-hours design doc (see [Deeper Context](#11-deeper-context)). This is the
engineering source of truth; where it and FEATURES.md overlap, FEATURES owns *look/feel* and
DESIGN owns *mechanism*.

---

## 1. The one risky loop

The entire product is one loop. Everything else (frecency, tokens, adaptive cards) is toppings on
a pizza you haven't proven you can bake. Prove the loop first (the spike), then build around it.

```
                ┌────────────────────────────────────────────────────────────┐
   ⌥Space ─────▶│ 1. capture NSWorkspace.frontmostApplication  (BEFORE panel) │
   (Carbon,     └────────────────────────────────────────────────────────────┘
   consumed)                                  │
                                              ▼
                ┌────────────────────────────────────────────────────────────┐
                │ 2. show nonactivating NSPanel (.nonactivatingPanel, float)  │
                │ 3. fuzzy filter in-memory prompts (40ms debounce)           │
                └────────────────────────────────────────────────────────────┘
                                              │  ↵
                                              ▼
                ┌────────────────────────────────────────────────────────────┐
                │ 4. dismiss/fade panel + re-assert captured app as target    │
                │ 5. PasteService.paste(text, into: capturedApp)              │
                │        Strategy B (AX direct write)  ── primary             │
                │        Strategy A (clipboard + ⌘V)   ── fallback            │
                │ 6. fade complete (~120ms); clipboard restored if A used     │
                └────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
                              text in the host app's field, cursor placed,
                              focus never left the host app
```

### Loop invariants (name them so races can't creep in)

1. **capture-before-present** — snapshot the frontmost app *before* the panel appears, or you
   paste into your own panel.
2. **paste-targets-captured-app-not-current-frontmost** — at ↵, paste into the *captured* app,
   re-asserted as target, not whatever is frontmost now (an app switch mid-palette must not
   redirect the paste).
3. **main-thread-only** — all AX and AppKit calls run on the main thread (AX is main-thread-affine).
4. **panel-on-captured-app-display** — the target `NSScreen` is part of the capture snapshot (a
   corollary of invariant 1): derive it from the captured app's key window and center the panel
   there, falling back to `NSScreen.main` if it can't be resolved. The panel must not appear on the
   mouse's screen or on whatever is frontmost *now* — it appears where the captured app lives, so
   the hand learns one position (FEATURES §1 → Position).

---

## 2. Paste service — the heart

Two strategies. **Build B before A on purpose**, so B is real and you don't ship A and rationalize
the clipboard-clobber bug as "good enough."

### 2.1 Verify by read-back, not by return code

After **every** paste attempt (B *and* A), read `kAXValueAttribute` (or `kAXSelectedTextRange`) of
the focused element and **assert the marker actually landed** at the expected position. An AX
`set` returning `.success` from an Electron/WebKit shim that silently no-ops is the *exact* failure
this whole project is structured to avoid. The spike's exit criterion is "marker confirmed in the
field by read-back AND clipboard byte-identical," never "the set call returned `.success`."

### 2.2 B-vs-A is a capability probe, not a fall-through

Read the focused element first, inspect what it supports, then choose the path from evidence:

| Focused element supports | Field state | Path |
|--------------------------|-------------|------|
| `kAXSelectedTextAttribute` settable | any | **B — selected-text** (insert at caret, non-destructive). *Preferred.* |
| not selected-text-settable, but `kAXValue` settable | **empty** | **B — value-set** (safe: nothing to clobber). |
| not selected-text-settable, value-set only | **non-empty** | **A** — never value-set. (Clobber ban, §2.3.) |
| focused element unreadable / role unknown (typical Electron) | any | **A directly.** |

Probe via `AXUIElementIsAttributeSettable` on `kAXSelectedTextAttribute`, presence of
`kAXSelectedTextRange`, and the element role.

### 2.3 Clobber ban (HARD RULE)

`kAXValueAttribute` value-set is permitted **only when read-back confirms the field was empty.**
On a non-empty field it would replace the entire contents — turning "drop the prompt in" into
"delete your half-written email." Never do it.

### 2.4 Strategy A — clipboard + synthesized ⌘V

Snapshot **all** pasteboard items/types → set the string → synthesize ⌘V via `CGEvent`
(virtual keycode 9, `.maskCommand`, `.cgAnnotatedSessionEventTap`) → **restore all types**.

**Clipboard restore (HARD RULE: never leave the clipboard mutated).** Restore is driven by
**polling `NSPasteboard.changeCount`** to detect the target consuming the paste, with ~120ms as a
*ceiling*, not the mechanism. A blind 120ms sleep is fine for the spike but races under app-switch
contention (a momentarily-busy Electron target may not have read the pasteboard yet). Restore must
survive an app-switch landing mid-paste.

### 2.5 `{{cursor}}` asymmetry (document now, implement in stage 3)

- **B path:** can set `kAXSelectedTextRange` after insert to place the caret precisely. Clean.
- **A path:** synthesized ⌘V leaves the caret at end-of-paste, no control.

So `{{cursor}}` is a **B-path-only precise feature**; on A it degrades to "caret at end." Stage 3
must not promise placement the fallback can't honor.

---

## 3. Global hotkey

**Carbon `RegisterEventHotKey`.** ⌥Space must be reliable everywhere and, critically, **consumed**
so the keystroke never reaches the host app (an `NSEvent` global monitor physically *cannot*
consume — ⌥Space would leak through and insert a space / trigger a host shortcut). Old API, but
the stable standard for this class of tool. Wrap it behind a `HotkeyManager` protocol so swapping
to a `CGEventTap` later is a one-file change. The default is ⌥Space; the menu-bar dropdown offers
one **rebind** affordance (no settings window) so a collision never kills the project.

---

## 4. Accessibility permission

Both paste paths need Accessibility (`AXIsProcessTrustedWithOptions`). Two facts to internalize:

- **Two identities.** Running `swift PasteProbe.swift` grants **Terminal**; the real app grants the
  bundled **`.app`**. **The grant does NOT transfer** between them — expect a "but it worked
  yesterday" moment when moving from spike to app.
- **First-run is lazy** (see FEATURES §4): the first ⌥Space without trust opens the one-screen
  prompt; a dimmed menu-bar icon is the persistent reminder.

### 4.1 The Accessibility re-grant tax (the worst silent failure) — and the fix

macOS TCC keys a permission grant on the binary's **signature + bundle ID + path**. A fresh
`xcodebuild` of an unsigned/ad-hoc-changing binary looks like a *new app*, so the OS **silently
revokes Accessibility** — the app launches, the hotkey fires, and nothing pastes, with no error.
Left unsolved this masquerades as "the paste loop regressed" and burns hours debugging a loop that
already passed the spike.

**Fix, applied from the very first app build:**
1. **Stabilize `PRODUCT_BUNDLE_IDENTIFIER`** and **ad-hoc code-sign** (`CODE_SIGN_IDENTITY="-"`) so
   successive builds are the *same* app to macOS and keep the grant. (Highest-leverage DevEx fix.)
2. **Build to a fixed install path** (e.g. `~/Applications/Promptly.app`) — TCC keys partly on path.
3. Escape hatch when it does get confused: `tccutil reset Accessibility <bundle-id>`.

Surface AX status **loudly at runtime**: check `AXIsProcessTrusted()` on launch and every hotkey
fire; if false, the menu-bar icon goes to an alert state and logs `AX NOT GRANTED — paste will
fail`. This turns the worst silent failure into a one-glance diagnosis.

---

## 5. MVP module decomposition

Flat, one file each. Keep it minimal but clean.

| Module | Responsibility |
|--------|----------------|
| `main.swift` / `AppDelegate` | `@main`, `LSUIElement` (no Dock icon), status item; owns the others. |
| `HotkeyManager` | Registers ⌥Space (Carbon), fires a closure. Mechanism swappable behind one protocol. |
| `PanelController` | Owns the `.nonactivatingPanel`, the filter field, the results list. `present(captured:)` / `dismiss()`. **Opaque `#0f0f14` content view at 6px radius — NOT `NSVisualEffectView`; bundle + register JetBrains Mono (fallback `.monospacedSystemFont`). Visual system: FEATURES §0.** Also owns: the **fixed-height 6-row scrolling viewport** (scroll-past-6, clamp at full-list ends — FEATURES §1), the **zero-prompts state** (A0) and persistent footer (FEATURES §2), screen targeting per **invariant 4**, and the **Reduce-Motion / Increase-Contrast / VoiceOver** behavior (FEATURES §9). `present(captured:)` takes the captured app's screen, not just the app. |
| `PasteService` | The spike's two strategies + capability probe + read-back, behind one `paste(_:into:) -> Result`. **Only module that must not drift from spike behavior — extract it verbatim.** |
| `PromptStore` | Loads markdown-per-file prompts (§7) **recursively** (subfolders = folders, §7.1), live-reload via **FSEvents** (§7.2), in-memory `[Prompt]` + fuzzy filter, frecency ranking, and pure pin resolution (`resolvePins`, §7.3). No DB. |
| `HudRow` | Pure ⌥1–9 slot assignment: hybrid pins-then-frecency `assign(pins:ranked:)` (§7.4). UI-free so it is Tier-A testable. |
| `Capture` | Thin wrapper for the `frontmostApplication` snapshot, so ordering (invariant 1) is enforced in one place. |

### 5.1 The off-paste-path window invariant (Stage 9)

The Library window (`LibraryWindowController`, Stage 9) is a **normal activating
`NSWindow`** — titled, resizable, and explicitly *allowed* to take real keyboard focus. That looks
like a violation of the project's "never steal focus" framing, so name precisely why it isn't:

**That framing exists to protect the ⌥Space paste loop specifically.** Stealing focus is fatal there
because the loop must paste back into the *captured* host app (invariants 1–2): if our own UI becomes
key, the captured target is wrong and the paste lands in the panel. The Library window is **entirely
off that loop** — it never calls `Capture`, never calls `PanelController.present()`, never calls
`PasteService`. It only browses, searches, creates, edits, organizes, and pins, writing through
`PromptStore` (which writes files + reloads). Because it never pastes into another app, capture-
before-show is irrelevant to it, and there is no host-app focus to protect. The fast ⌥Space palette
(`PanelController`, a `.nonactivatingPanel`) is untouched and remains the only focus-sensitive
surface.

This window also **replaces the modal `PromptEditorPanel`**: its detail pane becomes the single
editor, and `PromptEditorPanel` is retired in Stage 9 (the full window decomposition — sidebar/list/
detail, `NSSplitViewController` tuning, scope model — lives in that stage file, not here). The
architectural invariant DESIGN owns is the one above: *a surface is allowed to take focus iff it is
off the paste loop.*

---

## 6. Threading & timing budget (~700ms feel)

- All AX/AppKit on the **main thread**.
- Filter **40ms debounce**; in-memory fuzzy match over a few dozen prompts is sub-millisecond.
- Commit: ~80ms selected-row pulse → ~120ms panel fade, paste fired under the fade.
- Sequence at ↵: dismiss/fade panel **and re-assert captured app as target before pasting**
  (invariant 2), then paste, then complete fade.
- **Reduce Motion:** when `accessibilityDisplayShouldReduceMotion` is set, skip the pulse and the
  0.98 scale — use an instant or short opacity-only dismiss. The ~700ms feel is about latency, not
  animation; dropping the choreography never delays the paste (FEATURES §2 State D, §9).

---

## 7. Prompt storage — markdown file per prompt

One `.md` file per prompt in a **visible, one-`open`-away folder** (e.g. `~/Prompts/`), held as a
**single code constant** so moving it later (to Application Support, with a migration) is trivial.
Chosen over strict JSON because prompts are inherently multi-line and JSON's `\n`-escaping is
miserable to hand-edit; markdown is multi-line-native, zero-dependency, and diffable. The tradeoff
is a little custom frontmatter parsing.

**File shape (frontmatter + body):**

```markdown
---
name: PR description
keywords: [pr, pull request, diff]
pin: 3
description: Structured diff summary for a PR
---
Summarize this diff for a PR description. Cover: what changed, why, risk, and how to test.

{{clipboard}}
```

- `name` — the search label (required).
- `keywords` — optional fuzzy aliases.
- `pin` — optional `Int` 1–9: the manually-claimed ⌥-number (Stage 8). Absent = unpinned.
  Out-of-range or garbage values parse to `nil` (unpinned), never an error — the valid set mirrors
  `HudRow.slotCount` and is held as `PromptStore.pinSlots = 1...9`.
- `description` — optional single line, surfaced in the Library list (Stage 9). Emitted only when
  non-empty.
- body — the prompt text, may contain tokens.
- **`pin`/`description` are emitted only when present** (`serialize`), so an unpinned/undescribed
  file stays byte-clean — no spurious keys appear when an existing flat prompt is saved through the
  editor for an unrelated reason.
- **Fail loudly on load:** bad frontmatter / unreadable file → menu-bar alert + a logged line
  (filename); duplicate `name` → logged warning. ~90% of a linter's value at the load site, with
  nothing to maintain. A real lint is deferred until ~50 prompts or first sharing.

### 7.1 Folders are subdirectories, not frontmatter (Stage 8)

A prompt's **folder is derived from its parent directory** under `~/Prompts/`, never written to
frontmatter: `~/Prompts/Engineering/foo.md` → `folder = "Engineering"`; a root-level file →
`folder = ""`. The directory *is* the folder — there is no second source of truth to drift, and
organizing the library is plain Finder/`mv`, not an editor round-trip. `Prompt` gains `folder`,
`pinnedSlot`, and `description`; `title` is a UI alias for `name` (the frontmatter key stays `name`).

**`filename` is now a path relative to `~/Prompts`** (`"foo.md"` or `"Engineering/foo.md"`), and it
is simultaneously (a) the usage/frecency dict key, (b) the dedup key, and (c) the file locator. That
triple duty drives the migration guarantee:

- **Existing flat prompts are unaffected.** A root file keeps its bare `"foo.md"` filename, so its
  usage key is byte-identical to the Stage-1…7 key — frecency history carries over with no migration
  step. Old files are never rewritten on load; they gain `pin:`/`description:` only when next saved
  through the editor.
- **A folder *move* must migrate the usage key.** Moving a prompt changes its relative path, hence
  its `filename`, hence its usage key. The move operation (`PromptStore.move(_:toFolder:)`, Stage 9)
  must carry `usage[old] → usage[new]` or frecency silently resets to zero for that prompt — a
  data-loss bug that looks like "it just dropped down the list."

### 7.2 Recursive scan + FSEvents watch (Stage 8)

The Stage-1-era loader walked only the top level: `contentsOfDirectory` for the initial load and a
single-fd `DispatchSource` watch on `~/Prompts` itself. Subfolders are invisible to both. Stage 8
replaces them:

- **Initial load → `FileManager.enumerator`** (recursive, `[.skipsHiddenFiles,
  .skipsPackageDescendants]`), collecting every `.md` under the tree in a stable path-sorted order
  (load order is deterministic — frecency cold-start and dedup both lean on it). Each file's relative
  path becomes its `filename`; the parent component becomes its `folder`. The first-launch seed check
  counts the *whole* tree, so a library living entirely in subfolders is not mistaken for empty and
  re-seeded.
- **Live reload → an `FSEventStream`** rooted at `~/Prompts` (`kFSEventStreamCreateFlagFileEvents`,
  ~200ms latency to coalesce a burst — e.g. a multi-file move — into one reload), dispatched to the
  main queue, calling `load()`. This sees the whole subtree, which the single-fd source could not.
- **Self-write suppression.** `save()`/`delete()` write the file *and* call `load()` directly, then
  set a brief `suppressReloadUntil` window (~0.3s); the FSEvents callback ignores events inside that
  window so an in-app edit doesn't trigger a redundant second reload. External edits (Finder, an
  editor) fall outside the window and still reload normally.

`load()` ends by firing an optional `onReload` hook — no subscriber in Stage 8; the Stage 9 Library
window uses it to refresh sidebar counts and the list. (CoreServices is linked for `FSEventStream`.)

### 7.3 Pin resolution — deterministic and non-destructive (Stage 8)

Two files can declare the same `pin:`. Resolution is a **pure** function so it is Tier-A testable
without a filesystem:

```
static func resolvePins(_ prompts: [Prompt]) -> (pins: [Int: Prompt], conflicts: [PinConflict])
```

- **Lowest `filename` wins** a contested slot (a stable, content-independent tiebreak). The loser is
  reported as a `PinConflict(slot, winner, loser)` and **treated as unpinned for assignment**.
- **The loser's file is left untouched on disk** — no silent rewrite at load. A load is read-only
  with respect to the prompt files; the only place a `pin:` is rewritten is a *user-initiated* steal
  in the Library editor (Stage 9). `pinnedAssignment()` wraps `resolvePins().pins`; the Library
  surfaces the conflicts.

This is the load-time guarantee that pairs with the hybrid HUD assignment in §7.4: a conflicted pin
contributes nothing to the frozen slot map beyond its winner, and nothing on disk changes behind the
user's back.

### 7.4 Hybrid HUD assignment + the freeze invariant (Stage 8)

Stage 7 made the ⌥1–9 HUD *adaptive*: fixed positions, contents auto-sorted by frecency ("a
keyboard, not a piano"). Stage 8 layers manual pins on top without replacing that — a single pure
function in `HudRow`:

```
static func assign(pins: [Int: Prompt], ranked: [Prompt]) -> [Int: Prompt]
```

- **Pins claim their chosen slot first**; the frecency `ranked` ordering fills only the slots that
  remain. A pinned prompt is removed from the fill stream (deduped by `filename`) so it never also
  appears in a frecency-filled slot. Pure, deterministic (identical `(pins, ranked)` → identical
  map), 1-based, capped at 9. With empty `pins` it degrades exactly to the Stage-7 behavior — the
  regression anchor.

**This composes with the Stage-7 freeze invariant; it does not weaken it.** The assignment is still
computed **once per panel appearance** in `PanelController.present()` and held constant until
dismiss — ⌥3 fires the same prompt for the whole appearance even while the filter changes the visible
rows. Stage 8 extends the frozen state by one item: **which filenames are pinned** is also snapshotted
at `present()`, alongside the slot map. Concretely, `present()` freezes three derived maps together
(`hudAssignment`, `hudSlotByFilename`, `hudPinnedFilenames`) from one read of the store, so a pin
that changes on disk mid-appearance cannot diverge the chip from the key it fires. The chip in
`PromptCellView.configure` reads from those frozen maps: it shows `⌥N` when the query is empty **or**
the prompt is pinned (a pin is a persistent promise, so its chip survives filtering), and styles a
pinned chip as "permanent" (brighter primary, medium weight) versus a frecency-filled "today's guess"
(dim footer, regular weight). This is a draw-and-data change only — no height or resize math is
touched, so the ask-mode frame-freeze (§6) is untouched.

---

## 8. Token grammar

`{{token}}` syntax. MVP+stage-3 tokens: `{{clipboard}}`, `{{date}}`, `{{cursor}}`, later
`{{ask:label}}`. Rules:

- **Unknown tokens stay literal** — paste `{{whatever}}` verbatim so typos are visible (there's no
  help panel; visible failure is how the grammar is learned).
- Known tokens with empty values substitute empty, with a logged warning.
- Discoverability without a settings panel: a header comment block in the prompt files + a seed
  **"token cheatsheet"** prompt that demonstrates every token (the docs live *inside* the product
  and surface via the palette).

---

## 9. Logging (`os_log` from MVP)

The paste loop is invisible (no UI, focus never stolen), so a missing grant or a silent paste
failure is otherwise indistinguishable from a real bug after months away. Log four events with
`os_log`: **AX status**, **strategy chosen** (B-selected / B-value / A), **paste result**
(read-back confirmed?), **clipboard restore confirmed**. README carries the
`log stream --predicate …` one-liner to watch them live.

---

## 10. Build, run, distribute

- **Spike:** `swift PasteProbe.swift` (native arm64).
- **App:** built **native arm64 by default** (Universal arm64+x86_64 on release), ad-hoc signing,
  fixed bundle ID, fixed install path — all wrapped in **`run.sh`** (the whole dev loop: build →
  install → kill → relaunch → tail log). `run.sh` is THE command in the README.
- **Distribution:** deferred. Build & run locally from Xcode/`run.sh`. When handing to someone:
  direct `.app` zip or a Homebrew cask; **notarization** (Developer ID + `notarytool`) only then —
  don't script it until it's needed. No CI/CD; a manual build+notarize script is plenty until v1.

---

## 11. Deeper context

Full original vision, the office-hours reasoning, the spike spec, and "what I noticed about how
you think":
`~/.gstack/projects/MattModeCode-ai-prompt-shortcut-app/mc-main-design-20260618-225221.md`
