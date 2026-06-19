# DESIGN — Technical Design

**Status:** Pre-scaffold · **Stack:** native Swift / AppKit · **Arch:** Apple Intel (x86_64)
Sibling docs: [PRD.md](PRD.md) · [FEATURES.md](FEATURES.md) · [TASKS.md](TASKS.md)

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
2. **Build to a fixed install path** (e.g. `~/Applications/PromptPalette.app`) — TCC keys partly on path.
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
| `PanelController` | Owns the `.nonactivatingPanel`, the filter field, the results list. `present(captured:)` / `dismiss()`. |
| `PasteService` | The spike's two strategies + capability probe + read-back, behind one `paste(_:into:) -> Result`. **Only module that must not drift from spike behavior — extract it verbatim.** |
| `PromptStore` | Loads markdown-per-file prompts (§7), live-reload, in-memory `[Prompt]` + fuzzy filter. No DB. |
| `Capture` | Thin wrapper for the `frontmostApplication` snapshot, so ordering (invariant 1) is enforced in one place. |

---

## 6. Threading & timing budget (~700ms feel)

- All AX/AppKit on the **main thread**.
- Filter **40ms debounce**; in-memory fuzzy match over a few dozen prompts is sub-millisecond.
- Commit: ~80ms selected-row pulse → ~120ms panel fade, paste fired under the fade.
- Sequence at ↵: dismiss/fade panel **and re-assert captured app as target before pasting**
  (invariant 2), then paste, then complete fade.

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
---
Summarize this diff for a PR description. Cover: what changed, why, risk, and how to test.

{{clipboard}}
```

- `name` — the search label (required).
- `keywords` — optional fuzzy aliases.
- body — the prompt text, may contain tokens.
- **Live-reload:** a `DispatchSource` file-watcher (no dependency) reloads the in-memory array on
  save — the cheapest possible CRUD, buys months of runway before stage-2 in-app CRUD.
- **Fail loudly on load:** bad frontmatter / unreadable file → menu-bar alert + a logged line
  (filename); duplicate `name` → logged warning. ~90% of a linter's value at the load site, with
  nothing to maintain. A real lint is deferred until ~50 prompts or first sharing.

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

- **Spike:** `arch -x86_64 swift PasteProbe.swift`.
- **App:** `xcodebuild` with `ARCHS=x86_64` (+ `VALID_ARCHS` accordingly), ad-hoc signing, fixed
  bundle ID, fixed install path — all wrapped in **`run.sh`** (the whole dev loop: build → install
  → kill → relaunch → tail log). `run.sh` is THE command in the README.
- **Distribution:** deferred. Build & run locally from Xcode/`run.sh`. When handing to someone:
  direct `.app` zip or a Homebrew cask; **notarization** (Developer ID + `notarytool`) only then —
  don't script it until it's needed. No CI/CD; a manual build+notarize script is plenty until v1.

---

## 11. Deeper context

Full original vision, the office-hours reasoning, the spike spec, and "what I noticed about how
you think":
`~/.gstack/projects/MattModeCode-ai-prompt-shortcut-app/mc-main-design-20260618-225221.md`
