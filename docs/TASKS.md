# TASKS — Gated Build Checklist

Solo, weekend-burst friendly: each box is sized to finish in one sitting, and each **stage names
the friction signal that authorizes the next**. Don't pre-build later stages — let real use pull them.

Sibling docs: [PRD.md](PRD.md) · [FEATURES.md](FEATURES.md) · [DESIGN.md](DESIGN.md) · [FEATURE-CATALOG.md](FEATURE-CATALOG.md) · [stages/](stages/) · [AGENT-WORKFLOW.md](AGENT-WORKFLOW.md)

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done.

---

## 🚦 GATE 0 — The spike (NOTHING past this line until 5/5 green)

`PasteProbe.swift` exists and typechecks for x86_64. Extend it, then run it against all 5 targets.

**Extend the spike:**
- [x] Add **read-back verification** — after each attempt (B and A), read `kAXValueAttribute` /
  `kAXSelectedTextRange` and assert the marker actually landed. (Exit criterion is read-back, not `.success`.)
- [x] Add a **per-target evidence dump** — focused-element role, is-settable(selected-text), is-settable(value),
  which strategy fired, read-back result. (~30 lines; becomes the empirical basis for the §2.2 decision table.)
- [x] **[review D1] Target the captured app by pid** — `AXUIElementCreateApplication(pid)` →
  `kAXFocusedUIElementAttribute`, NOT system-wide focus. Implements invariant 2 in code. (`copyFocusedElement(forPid:)`.)
- [x] **[review D2] Run under a nonactivating KEY panel** — bring up a `.nonactivatingPanel` that becomes
  key before probing; log the divergence (system-wide focus → the panel field; pid-targeted → the host field).
  This reproduces the app's real runtime condition the bare spike skipped. (`makeKeyProbePanel`.)
- [x] **[review A3] Anchor read-back on the length delta** — confirm the field grew by exactly `marker.count`
  (or equals it for a value-set into an empty field), not a naive `contains()` that false-positives. (`ReadBack`.)

> **Manual run still required (author):** `arch -x86_64 swift PasteProbe.swift`, click into each app within
> the lead time, grant Accessibility to Terminal. The new evidence rows to read: **panel was KEY**,
> **system-wide role** (expect the panel field), **pid-targeted role** (expect the host field). The gate
> passes only if the pid-targeted read finds the host field with the panel key.

**Run the matrix** — `arch -x86_64 swift PasteProbe.swift`, click into a field in each app within the lead time:

| Target | Engine / failure mode | Tier | B (AX write) | A (clipboard) | Clipboard clean after | Read-back confirmed |
|--------|-----------------------|------|:---:|:---:|:---:|:---:|
| Terminal | native AppKit + self-paste | **must-pass** | [ ] | [ ] | [ ] | [ ] |
| Safari | WebKit text fields | **must-pass** | [ ] | [ ] | [ ] | [ ] |
| Xcode | Apple text engine | **must-pass** | [ ] | [ ] | [ ] | [ ] |
| VSCode | Electron | known-hostile | [ ] | [ ] | [ ] | [ ] |
| Notes | sandboxed | known-hostile | [ ] | [ ] | [ ] | [ ] |

> **GATE: all 3 must-pass targets confirmed by read-back AND clipboard byte-identical before ANY app code.**
> The two **known-hostile** targets (Electron, sandboxed) must reach **at least the clipboard fallback (A)
> with a clean clipboard** — a clean-clipboard A-path paste is an acceptable pass for them; a *silent
> read-back failure that also clobbers or loses clipboard contents* is NOT, and still blocks. Document
> each hostile-target outcome as a known limitation in DESIGN §2.2 rather than letting it stall the MVP.
> Fix every failure here, in ~80 lines, before it's buried under SwiftUI.
>
> *Rationale (CEO review): the bet is "crosses over in **your** week." A hard read-back miss on an app
> you don't draft prompts in daily shouldn't block a working palette in the three you live in. Rigor is
> preserved (no clobber, no clipboard loss, ever); only the all-or-nothing framing is relaxed.*
>
> *Note: this step is run by the author — it needs clicking into each app and granting
> Accessibility to Terminal. The grant does NOT transfer to the app later (DESIGN §4).*

---

## Stage 1 — MVP menu-bar palette

**Exit criterion:** ⌥Space → filter → ↵ pastes the selected prompt into the frontmost app, cursor
correct, focus never stolen, ~700ms — **and you've reached for ⌥Space without thinking, once.**

- [x] Xcode menu-bar agent app: `LSUIElement`, no Dock icon, status item.
- [x] **From this first build:** ad-hoc signing (`CODE_SIGN_IDENTITY="-"`), stable
  `PRODUCT_BUNDLE_IDENTIFIER`, fixed install path, `ARCHS=x86_64`. Write **`run.sh`** (build →
  install → kill → relaunch → tail log).
- [x] `HotkeyManager` — Carbon `RegisterEventHotKey` for ⌥Space, consumed, behind a protocol.
- [x] `Capture` — snapshot `frontmostApplication` (enforce invariant 1).
- [x] `PanelController` — nonactivating `NSPanel`, filter field, results list; the four states (FEATURES §2).
- [x] `PasteService` — **extract the proven spike code verbatim** (capability probe + read-back + restore).
- [x] `PromptStore` — markdown-per-file loader (DESIGN §7) + `DispatchSource` live-reload + fuzzy filter.
- [x] Default state shows **top ~6 most-recently-used** (simple last-used timestamp; not the Stage-6
  frecency engine — cold launch falls back to seed order); selected row unmistakable; clamp on ↑/↓.
- [x] **Silent success, loud failure** (FEATURES §3); leave text on clipboard on failure.
- [x] **Lazy first-run** Accessibility screen + dimmed menu-bar icon when not granted (FEATURES §4).
- [x] Menu-bar dropdown: AX status, hotkey rebind, open prompts folder (FEATURES §5).
- [x] `os_log` four events (DESIGN §9); add the `log stream` one-liner to README.
- [x] **Seed a real library — 8–10 prompts you genuinely reach for** (not placeholders), plus the
  **"token cheatsheet"**. 10 prompts in `Resources/SeedPrompts/` with JetBrains Mono bundled.

**Manual verification (pending — author):** trigger ⌥Space from inside each of the 5 apps — paste +
cursor + no focus theft, latency feels sub-second; rebuild and confirm Accessibility **persists**.

---

## Stage 2 — Prompt store + CRUD

**Exit criterion:** you can add/edit/delete a prompt without hand-editing a file — *and you wanted
to, because hand-editing markdown finally got annoying* (that annoyance is the signal; not before).

- [x] `PromptStore.save(name:keywords:body:filename:)` — writes/overwrites `~/Prompts/<slug>.md` with YAML frontmatter + body.
- [x] `PromptStore.delete(_:)` — removes the file and purges its `lastUsed` entry.
- [x] `PromptEditorPanel` — dark-palette NSWindow with name/keywords/body fields; `forNew` and `forEdit` modes.
- [x] Panel ⌫ key (when filter empty) — confirmation alert → `PromptStore.delete()` → reload.
- [x] Panel ⌘E — opens editor pre-filled with selected prompt.
- [x] Status-bar "New Prompt…" — opens blank editor; Save writes a new file.
- [ ] **Manual verification:** status-bar → New Prompt → fill → Save → appears in ⌥Space list; open panel, select, ⌫ → confirm → gone.

---

## Stage 3 — Static tokens

**Exit criterion:** a prompt with `{{clipboard}}`/`{{date}}` assembles correctly at paste time.

- [x] `{{clipboard}}`, `{{date}}`, `{{cursor}}` (cursor precise on B path, caret-at-end on A — DESIGN §2.5).
- [x] Unknown tokens stay literal; empty known tokens log a warning.
- [ ] **Manual verification (author / Tier B):** paste a `{{clipboard}}`/`{{date}}` prompt into a B-path app (Terminal/Xcode) and an A-path app (VSCode); confirm assembly + caret position (precise on B, end-of-text on A).

---

## Stage 4 — `{{ask:label}}` inline expansion

**Exit criterion:** a `{{ask}}` prompt expands the palette in place into a fill-in flow without the
panel jumping; ↵/Tab advance, esc cancels the whole expansion.

- [x] In-place transform (no resize jump); progress indicator; multi-`{{ask}}` chaining.
- [ ] **Manual verification (author / Tier B):** run a 2–3 `{{ask}}` prompt end-to-end; confirm the panel never jumps/resizes, ↵/⇥ advance, esc cancels the whole expansion mid-flow.

---

## Stage 5 — Inverse capture hotkey

**Exit criterion:** select text anywhere → hotkey → a pre-filled "save as prompt" sheet writes a new markdown file.

- [x] Capture hotkey (⌥⇧Space) + save sheet (title field focused, body pre-filled). *Reuses `PromptEditorPanel` (activating); a nonactivating sheet is a future polish.*
- [ ] **Manual verification (author / Tier B):** select text in a real app, fire ⌥⇧Space, confirm the sheet pre-fills the body + focuses the title, Save, and the new prompt is searchable in ⌥Space.

---

## Stage 6 — Frecency + search

**Exit criterion:** ordering reflects what you actually use; only reach for FTS if in-memory filter
latency is *actually* felt (premature at <80 prompts).

- [x] Usage-ranked (frecency) ordering — frequency × 3-day-half-life recency decay; cold start degrades to seed order. FTS/SQLite **not** added (stays the ask-first boundary; premature <80 prompts).
- [ ] **Manual verification (author / Tier B):** over a week of real use, confirm the ordering tracks what you reach for.

---

## Stage 7 — Adaptive ⌥1–9 HUD row

**Exit criterion:** the row's positions are stable within an interaction and you trust ⌥3 to be ⌥3;
content adapts only between opens.

- [x] Fixed 9 positions, content reorders between opens, **no live reshuffle** — assignment frozen at present-time; ⌥1–9 fire the frozen slot; trailing ⌥-number chips on the resting top-9 rows (FEATURES §7).
- [ ] **Manual verification (author / Tier B):** confirm ⌥3 fires the same prompt for the whole time the row is up, and re-sorting only happens between opens.

---

## The real test (after Stage 1)

One week of daily personal use. If you reach for ⌥Space **reflexively**, it crossed over — that's
the only metric that ultimately matters.
