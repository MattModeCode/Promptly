# Stage 8 — Folders, manual pins, descriptions

**Status:** Built · **Depth:** tiered · **"You choose ⌥3; the rest still adapts."**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-7](STAGE-7-adaptive-hud-row.md) · → next [STAGE-9](STAGE-9-library-window.md)
Canonical: [FEATURES](../FEATURES.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

Stage 7 made ⌥1–9 a heads-up display whose *content* adapts by frecency — "a keyboard, not
a piano." Stage 8 hands the user a steering wheel over that display **without giving up the
adaptation**: you can **pin** up to nine prompts to the exact ⌥-numbers your hand already
trusts, and every slot you *don't* pin keeps auto-filling by frecency. The number stays the
constant; you now decide which constants are yours and which the app still guesses.

Alongside pinning, the same stage lets a growing library live in **folders** (real
subdirectories under `~/Prompts/`, derived — never frontmatter) and gives each prompt an
optional one-line **description**. Folders are watched recursively, so a prompt nested three
levels deep loads and live-reloads exactly like a flat one.

**The feeling it protects:** ⌥3 is *yours* the moment you pin it — a persistent promise the
HUD keeps even while you filter — while the slots you never claimed stay quietly smart.

**Off the risky loop:** this stage touches only the *contents* of the frozen HUD map and the
*drawing* of its chips. The hotkey → capture → paste path, the ask-mode frame freeze, and the
~700ms feel are untouched.

## 2. Entry gate

[STAGE-7](STAGE-7-adaptive-hud-row.md)'s adaptive assignment exists: ⌥1–9 are fixed positions
filled from a frecency ranking, frozen once per appearance. Stage 8 layers manual pins *over*
that ranking, so the Stage-7 freeze invariant and the `HudRow.assign` shape it ships are the
foundation this builds on.

## 3. Features in this stage

- **Manual pins** — `pin: N` (1–9) in a prompt's frontmatter claims that ⌥-number. Pins are
  the user's explicit choice; frecency fills every slot a pin didn't claim. ⌥1–9 stay
  **palette-only** — no new global hotkeys, no Carbon changes.
- **Hybrid HUD assignment** — pins first, frecency-fill second, in one frozen map per
  appearance. A pinned prompt never also appears in a frecency-filled slot.
- **Folders** — any subdirectory under `~/Prompts/` is a folder; a prompt's folder is
  **derived** from its parent directory (root = `""`), never stored in frontmatter.
- **Descriptions** — optional `description:` one-liner per prompt, carried for the Library
  list (surfaced in [Stage 9](STAGE-9-library-window.md)).
- **Recursive scan + recursive watch** — the whole `~/Prompts` tree is enumerated and watched
  via FSEvents, replacing the Stage-7 top-level-only `DispatchSource`.

## 4. UX

- A **pinned** prompt's ⌥N chip shows **even while you filter** — a pin is a persistent
  promise, so it never disappears behind a query. It's styled distinctly: brighter primary
  text, medium weight ("permanent").
- A **frecency-filled** chip only shows in the resting (empty-query) state, styled dim
  (footer text, regular weight) — "today's guess." The two weights let "mine" read
  differently from "the app's pick" at a glance.
- Chip numbers are the prompt's slot in the **frozen** assignment, not its row position — so
  ⌥3 fires the same prompt for the whole appearance even as filtering reorders the visible
  rows.
- **Pin conflict** (two files declaring the same ⌥-number): resolved deterministically and
  silently — the lower filename keeps the slot, the loser is treated as unpinned for this
  appearance. Neither file is rewritten. The conflict itself is surfaced to the user in the
  Library window ([Stage 9](STAGE-9-library-window.md)); here it never blocks or mangles.

## 5. Design / mechanism

### Data model ([`Prompt`](../../Promptly/PromptStore.swift))
`Prompt` carries `folder` (derived), `pinnedSlot: Int?`, and `description: String?` beside the
existing `name`/`keywords`/`body`/`filename`. `filename` is now the path **relative** to
`~/Prompts` (`"foo.md"` or `"Engineering/foo.md"`) — it is the usage/frecency key, the dedup
key, and the file locator. A `var title: String { name }` alias keeps the UI label decoupled
from the back-compat frontmatter key.

**Migration guarantee:** an existing flat prompt parses as `folder = ""`, `filename` unchanged
→ its usage/frecency history key is preserved. No file is rewritten on load; `pin:` /
`description:` appear only when a file is next saved through the editor.

### Parse / serialize ([`PromptStore`](../../Promptly/PromptStore.swift))
`parse` reads `pin:` (range-guarded to 1…9 via `PromptStore.pinSlots`; out-of-range or
non-numeric → unpinned) and `description:`, and derives `folder` from the relative filename via
`folder(forRelativePath:)`. `serialize` emits `pin:` / `description:` lines **only when
present**, so an unpinned/undescribed file stays byte-clean.

### Pin resolution (pure — `resolvePins`)
`static func resolvePins(_:) -> (pins: [Int: Prompt], conflicts: [PinConflict])` walks prompts
in filename order; the first to claim a slot wins, later claimants become `PinConflict(slot,
winner, loser)` and are dropped from the map. Deterministic (lowest filename wins),
non-destructive (no disk rewrite), and pure (no filesystem) so it is Tier-A testable.
`pinnedAssignment()` wraps `resolvePins().pins`.

### Hybrid assignment (pure — [`HudRow.assign`](../../Promptly/HudRow.swift))
`assign(pins:ranked:)` seeds the map with the pins, then fills every still-empty slot from the
frecency `ranked` list, skipping any prompt already pinned (deduped by filename). Same
`(pins, ranked)` → same map — exactly the freeze property Stage 7 depends on. A pin holds its
slot even past where frecency could reach (a high pin with a tiny library leaves the middle
slots empty rather than reshuffling).

### Freeze at present-time ([`PanelController.present`](../../Promptly/PanelController.swift))
`present()` computes `pins = promptStore.pinnedAssignment()`, then
`hudAssignment = HudRow.assign(pins:, ranked: promptStore.ranked())`, and freezes two
derived maps alongside it: `hudSlotByFilename` (filename → ⌥-number) and `hudPinnedFilenames`
(the pinned set). The cell renderer reads these frozen maps — never the live store — so a pin
edited on disk mid-appearance can't change the chips under the user's hand. This preserves the
Stage-7 freeze invariant verbatim; no height or `resizePanel()` math is touched (a draw-only
change). `tableView(_:viewFor:)` shows a chip when the prompt **is pinned OR the query is
empty**, and `PromptCellView.configure` styles it by the frozen `pinned` flag.

### Recursive scan + watch ([`PromptStore`](../../Promptly/PromptStore.swift))
`load()` enumerates every `.md` under `~/Prompts` via `FileManager.enumerator` (skipping hidden
files and package descendants), sorted by path for deterministic load order. `startWatching()`
uses an `FSEventStream` rooted at `~/Prompts` with `kFSEventStreamCreateFlagFileEvents`,
coalescing a burst into one reload (~200ms latency). A `suppressReloadUntil` window briefly
ignores the FSEvents fired by the app's own `save()` / `delete()` (which already reloaded
directly), so an in-app edit doesn't double-reload; external edits still fire. An `onReload`
hook runs at the end of `load()` for the Library window to subscribe to (no subscriber in this
stage). `save` / `delete` / `newSlug` join the folder into the path with
`withIntermediateDirectories: true` and scope slug uniqueness to the target folder.

## 6. Tests for this stage

Three Tier A files, each with its standalone compile+run command in its header. All pure — no
panel, no keys, no filesystem.

- **`HudAssignTests.swift`** — the hybrid `HudRow.assign`. Empty-pins regression (Stage-7
  pure-frecency behavior intact), pins claim their exact number regardless of rank, frecency
  fills only the gaps in order, no double-appearance for a pinned-and-ranked prompt, and a pin
  holds past frecency's reach. Run:
  ```bash
  arch -x86_64 swiftc -framework AppKit \
      -target x86_64-apple-macosx12.0 \
      Promptly/PromptStore.swift Promptly/HudRow.swift HudAssignTests.swift \
      -o /tmp/HudAssignTests && /tmp/HudAssignTests
  ```
- **`PinResolveTests.swift`** — `resolvePins` + the parse range guard. Deterministic
  lowest-filename winner on a two-way and a three-way conflict, non-conflicting pins pass
  through, unpinned ignored, and out-of-range / non-numeric pins dropped in `parse` before
  they ever reach `resolvePins`. Run:
  ```bash
  arch -x86_64 swiftc -framework AppKit \
      -target x86_64-apple-macosx12.0 \
      Promptly/PromptStore.swift PinResolveTests.swift \
      -o /tmp/PinResolveTests && /tmp/PinResolveTests
  ```
- **`PromptStoreTests.swift`** (extended) — serialize→parse symmetry for `pin` and
  `description` (together and apart), absent keys staying nil **and** byte-clean, folder
  derivation from a relative path (root / one level / nested), and a flat root prompt keeping
  its bare-filename usage key (back-compat). Run:
  ```bash
  arch -x86_64 swiftc -framework AppKit \
      -target x86_64-apple-macosx12.0 \
      Promptly/PromptStore.swift PromptStoreTests.swift \
      -o /tmp/PromptStoreTests && /tmp/PromptStoreTests
  ```

**Tier B (author-run):** `./run.sh`, then add `pin: 3` to a prompt and confirm ⌥Space shows
it as a styled `⌥3` that pastes on ⌥3, while an unpinned slot still auto-fills by frecency;
create `~/Prompts/Engineering/foo.md` and confirm it loads and that edits inside the subfolder
are picked up by the recursive watch; give two files `pin: 3` and confirm the deterministic
winner with neither file silently rewritten. The cross-app paste matrix and the
focus-never-stolen guarantee are unaffected and need no re-run beyond a sanity ⌥Space.

## 7. Build checklist

Canonical: [TASKS Stage 8](../TASKS.md#stage-8--folders-manual-pins-descriptions).

- [x] `Prompt` carries `folder` (derived), `pinnedSlot`, `description`; `filename` is relative
      to `~/Prompts`; flat prompts migrate with key + history intact.
- [x] `parse` reads `pin:` (range-guarded 1–9) and `description:`; `serialize` emits them only
      when present (byte-clean otherwise).
- [x] `resolvePins` resolves conflicts deterministically (lowest filename wins, loser
      untouched on disk, conflict reported).
- [x] `HudRow.assign(pins:ranked:)` is hybrid: pins first, frecency fills the gaps, no
      double-appearance, freeze rule intact.
- [x] `PanelController.present()` freezes the pins-first assignment plus
      `hudSlotByFilename` / `hudPinnedFilenames`; chips render from the frozen maps.
- [x] Pinned chips style distinctly (bright/medium) from frecency chips (dim/regular); a
      pinned chip shows even while filtering. Draw-only — no height/resize math touched.
- [x] Recursive scan (`FileManager.enumerator`) + recursive FSEvents watch with coalescing
      and self-write suppression replace the top-level `DispatchSource`.
- [x] Tier A green: `HudAssignTests`, `PinResolveTests`, `PromptStoreTests` all pass.

## 8. Exit criterion

Verbatim from [TASKS Stage 8](../TASKS.md#stage-8--folders-manual-pins-descriptions):

> You can pin a prompt to a chosen ⌥-number and it holds there as a persistent, distinctly
> styled chip — visible even while filtering — while every slot you didn't pin still adapts by
> frecency; prompts organize into real `~/Prompts` subfolders that load and live-reload
> recursively; and a duplicate pin resolves deterministically without rewriting either file.
