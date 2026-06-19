# Stage 1 — MVP menu-bar palette

**Status:** Pre-scaffold · **Tier:** Tier A green by agent; Tier B + felt reflex by author · **Depth:** specified deeply.

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-0](STAGE-0-spike.md) · → next [STAGE-2](STAGE-2-prompt-store-crud.md)
Canonical: [PRD](../PRD.md) · [FEATURES](../FEATURES.md) · [DESIGN](../DESIGN.md) · [TASKS](../TASKS.md) · [CLAUDE.md](../../CLAUDE.md)

> Assembled execution view; detail lives in the canonical docs. **Reference, don't duplicate.**

---

## 1. Intent

⌥Space → nonactivating panel → fuzzy filter → ↵ pastes the prompt into the frontmost
app, cursor correct, panel gone, ~700ms, **focus never stolen**
([PRD §5 MVP](../PRD.md#5-success-criteria)).

**The feeling it protects:** the half-second where you hit ↵ and start reading the
result before you consciously decided which prompt you wanted
([PRD §3](../PRD.md#3-the-target-feeling-the-real-spec)).

## 2. Entry gate

**[STAGE-0](STAGE-0-spike.md) is green — including Tier B.** All 3 must-pass targets
read-back-confirmed, clipboard byte-identical, hostile targets at clean-clipboard A.
The `PasteService` here is the spike extracted **verbatim**; if the spike isn't
proven, there is nothing trustworthy to extract.

## 3. Features in this stage

(From [FEATURE-CATALOG §2 → Stage 1](../FEATURE-CATALOG.md#stage-1--mvp-menu-bar-palette--stage-file).)

Menu-bar agent app · ⌥Space hotkey · frontmost-app capture · nonactivating panel +
filter + results · **Mattmode Mono visual system** · 6-row scrolling viewport ·
selected-row bar+fill · fuzzy filter + matched-char emphasis · **states A0/A/B/C/D** ·
persistent footer · keyboard model · `PasteService` (verbatim) · `PromptStore` +
live-reload · markdown file shape · silent-success/loud-failure · lazy Accessibility
window · dimmed menu-bar icon · menu-bar dropdown · `os_log` four events · **seeded
real library** · `PasteCore` extraction + Tier A suite · palette accessibility ·
multi-monitor targeting.

## 4. UX

Pixel source of truth: [`../design/variant-B.html`](../design/variant-B.html)
(approved `/design-shotgun` render). ASCII states show behavior; the render shows the look.

- **Anatomy + selected row:** [FEATURES §1](../FEATURES.md#1-palette-anatomy-mvp).
  ~560pt wide, 6px radius, opaque dark surface (tokens: [§0](../FEATURES.md#0-visual-system--mattmode-mono)), no border. **2px silver left-edge bar is
  the primary selection signal** (carries the glance); fill is reinforcement. Validate
  against the render at arm's length / with a squint.
- **The five states A0/A/B/C/D:** [FEATURES §2](../FEATURES.md#2-the-five-mvp-states) —
  empty library, recents default, active filter, no match, commit fade. Footer persists
  across A0/A/B/C; only State D drops it.
- **Paste feedback:** [FEATURES §3](../FEATURES.md#3-paste-feedback--silent-success-loud-failure) —
  silent success; loud failure stays and leaves text on the clipboard.
- **First-run Accessibility window:** [FEATURES §4](../FEATURES.md#4-first-run-accessibility-moment-lazy) —
  the **one** surface allowed to take focus.
- **Menu-bar dropdown:** [FEATURES §5](../FEATURES.md#5-menu-bar-dropdown-the-only-settings).
- **Keyboard model:** [FEATURES §6](../FEATURES.md#6-keyboard-model-mvp) — ↑/↓ clamp, no wrap.

**Visual tokens are single-sourced in [FEATURES §0](../FEATURES.md#0-visual-system--mattmode-mono)** — do not copy values into code comments or other docs; reference §0.

## 5. Design / mechanism

- **Module decomposition:** [DESIGN §5](../DESIGN.md#5-mvp-module-decomposition) —
  `main.swift`/`AppDelegate`, `HotkeyManager`, `PanelController`, `PasteService`,
  `PromptStore`, `Capture`. Flat, one file each.
- **`PasteService` extracted verbatim** from the spike — the only module that must not
  drift ([DESIGN §5](../DESIGN.md#5-mvp-module-decomposition);
  [CLAUDE.md Testability](../../CLAUDE.md)). See §6 for the `PasteCore` split.
- **Hotkey:** Carbon `RegisterEventHotKey`, consumed, behind a protocol
  ([DESIGN §3](../DESIGN.md#3-global-hotkey)). An `NSEvent` monitor *cannot* consume.
- **Invariants:** capture-before-present, paste-targets-captured-app, main-thread-only,
  panel-on-captured-app-display ([DESIGN §1](../DESIGN.md#1-the-one-risky-loop)).
  `present(captured:)` takes the captured app's **screen**, not just the app.
- **Accessibility permission + the TCC re-grant tax fix:** [DESIGN §4](../DESIGN.md#4-accessibility-permission)
  / [§4.1](../DESIGN.md#41-the-accessibility-re-grant-tax-the-worst-silent-failure--and-the-fix) —
  stable `PRODUCT_BUNDLE_IDENTIFIER` + ad-hoc sign + fixed install path, **from the
  first build**, all baked into `run.sh`.
- **Storage:** [DESIGN §7](../DESIGN.md#7-prompt-storage--markdown-file-per-prompt) —
  markdown-per-file in `~/Prompts/` (single code constant), `DispatchSource` live-reload,
  fail loudly on load.
- **Threading & ~700ms budget:** [DESIGN §6](../DESIGN.md#6-threading--timing-budget-700ms-feel).
- **Logging:** [DESIGN §9](../DESIGN.md#9-logging-os_log-from-mvp) — four events.
- **Build/run:** [DESIGN §10](../DESIGN.md#10-build-run-distribute) — `run.sh` is THE command.

## 6. Tests for this stage

Per [CLAUDE.md → Test & Self-Heal Loop](../../CLAUDE.md). **Tier A activates fully here**
once `PasteCore.swift` is extracted (the testability structure):

- **Typecheck gate** — `arch -x86_64 swiftc -typecheck …` exits 0.
- **Clipboard snapshot/restore round-trip** — pasteboard byte-identical after a Strategy A paste.
- **Capability-probe decision table** — feed synthetic `Evidence` to `choosePath`; assert
  every [DESIGN §2.2](../DESIGN.md#22-b-vs-a-is-a-capability-probe-not-a-fall-through) row
  incl. the clobber-ban branch.
- **In-process AX write + read-back** — focus an in-process `NSTextField`, run the paste,
  assert the marker landed by read-back.

**Testability split:** extract `choosePath`, `strategyB_selectedText`, `strategyB_valueSet`,
`strategyA_clipboardPaste`, `restoreClipboard`, `readBackConfirms`, `Evidence` into
`PasteCore.swift`; leave interactive `runProbe()` in `PasteProbe.swift`; compile tests via
`swiftc PasteCore.swift <Tests>.swift`. One source of truth so `PasteService` and tests
can't drift.

**Honesty rules bind here:** never weaken an assertion to go green; a read-back miss or a
non-clean clipboard is a *real bug*. Report which tier ran.

- **Tier B (author):** trigger ⌥Space from inside each of the 5 apps — paste + cursor +
  no focus theft, sub-second feel; **rebuild and confirm Accessibility persists** (the
  stable-bundle-ID fix).

## 7. Build checklist

Canonical: [TASKS Stage 1](../TASKS.md#stage-1--mvp-menu-bar-palette).

- [ ] Xcode menu-bar agent app: `LSUIElement`, status item.
- [ ] Build hygiene from first build: ad-hoc sign, stable bundle ID, fixed path, `ARCHS=x86_64`; write `run.sh`.
- [ ] `HotkeyManager` (Carbon, consumed, behind protocol).
- [ ] `Capture` (frontmost snapshot, invariant 1).
- [ ] `PanelController` (nonactivating panel, filter, results, the states — FEATURES §2; opaque surface + JetBrains Mono per FEATURES §0, **not** `NSVisualEffectView`).
- [ ] `PasteService` — extract spike code **verbatim**.
- [ ] `PromptStore` — markdown loader + `DispatchSource` live-reload + fuzzy filter.
- [ ] Default state: top ~6 most-recently-used (last-used timestamp; cold launch → seed order).
- [ ] Silent success, loud failure; leave text on clipboard on failure.
- [ ] Lazy first-run Accessibility window + dimmed menu-bar icon.
- [ ] Menu-bar dropdown (AX status, hotkey rebind, open prompts folder).
- [ ] `os_log` four events; add the `log stream` one-liner to README.
- [ ] Seed a real library — 8–10 genuine prompts + the token cheatsheet.
- [ ] Extract `PasteCore.swift` + write the Tier A test file.

## 8. Exit criterion

Verbatim from [TASKS Stage 1](../TASKS.md#stage-1--mvp-menu-bar-palette):

> ⌥Space → filter → ↵ pastes the selected prompt into the frontmost app, cursor correct,
> focus never stolen, ~700ms — **and you've reached for ⌥Space without thinking, once.**

The seeded library must be real enough that you'd actually use ⌥Space instead of typing
the prompt by hand. The felt "reached for it without thinking" half is **author-only** — an
agent cannot certify it.
