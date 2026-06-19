# TASKS — Gated Build Checklist

Solo, weekend-burst friendly: each box is sized to finish in one sitting, and each **stage names
the friction signal that authorizes the next**. Don't pre-build later stages — let real use pull them.

Sibling docs: [PRD.md](PRD.md) · [FEATURES.md](FEATURES.md) · [DESIGN.md](DESIGN.md)

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done.

---

## 🚦 GATE 0 — The spike (NOTHING past this line until 5/5 green)

`PasteProbe.swift` exists and typechecks for x86_64. Extend it, then run it against all 5 targets.

**Extend the spike:**
- [ ] Add **read-back verification** — after each attempt (B and A), read `kAXValueAttribute` /
  `kAXSelectedTextRange` and assert the marker actually landed. (Exit criterion is read-back, not `.success`.)
- [ ] Add a **per-target evidence dump** — focused-element role, is-settable(selected-text), is-settable(value),
  which strategy fired, read-back result. (~30 lines; becomes the empirical basis for the §2.2 decision table.)

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

- [ ] Xcode menu-bar agent app: `LSUIElement`, no Dock icon, status item.
- [ ] **From this first build:** ad-hoc signing (`CODE_SIGN_IDENTITY="-"`), stable
  `PRODUCT_BUNDLE_IDENTIFIER`, fixed install path, `ARCHS=x86_64`. Write **`run.sh`** (build →
  install → kill → relaunch → tail log).
- [ ] `HotkeyManager` — Carbon `RegisterEventHotKey` for ⌥Space, consumed, behind a protocol.
- [ ] `Capture` — snapshot `frontmostApplication` (enforce invariant 1).
- [ ] `PanelController` — nonactivating `NSPanel`, filter field, results list; the four states (FEATURES §2).
- [ ] `PasteService` — **extract the proven spike code verbatim** (capability probe + read-back + restore).
- [ ] `PromptStore` — markdown-per-file loader (DESIGN §7) + `DispatchSource` live-reload + fuzzy filter.
- [ ] Default state shows **top ~6 most-recently-used** (simple last-used timestamp; not the Stage-6
  frecency engine — cold launch falls back to seed order); selected row unmistakable; clamp on ↑/↓.
- [ ] **Silent success, loud failure** (FEATURES §3); leave text on clipboard on failure.
- [ ] **Lazy first-run** Accessibility screen + dimmed menu-bar icon when not granted (FEATURES §4).
- [ ] Menu-bar dropdown: AX status, hotkey rebind, open prompts folder (FEATURES §5).
- [ ] `os_log` four events (DESIGN §9); add the `log stream` one-liner to README.
- [ ] **Seed a real library — 8–10 prompts you genuinely reach for** (not placeholders), plus the
  **"token cheatsheet"**. *A thin library never becomes a reflex; this is the cold-start that decides
  whether the week-long bet even gets a fair test (CEO review: top risk to "crosses over").*

**Manual verification:** trigger ⌥Space from inside each of the 5 apps — paste + cursor + no focus
theft, latency feels sub-second; rebuild and confirm Accessibility **persists** (the stable-bundle-ID fix).
**The seeded library is real enough that you'd actually use ⌥Space instead of typing the prompt by hand.**

---

## Stage 2 — Prompt store + CRUD

**Exit criterion:** you can add/edit/delete a prompt without hand-editing a file — *and you wanted
to, because hand-editing markdown finally got annoying* (that annoyance is the signal; not before).

- [ ] In-app add/edit/delete writing the same markdown files. (No DB.)

---

## Stage 3 — Static tokens

**Exit criterion:** a prompt with `{{clipboard}}`/`{{date}}` assembles correctly at paste time.

- [ ] `{{clipboard}}`, `{{date}}`, `{{cursor}}` (cursor precise on B path, caret-at-end on A — DESIGN §2.5).
- [ ] Unknown tokens stay literal; empty known tokens log a warning.

---

## Stage 4 — `{{ask:label}}` inline expansion

**Exit criterion:** a `{{ask}}` prompt expands the palette in place into a fill-in flow without the
panel jumping; ↵/Tab advance, esc cancels the whole expansion.

- [ ] In-place transform (no resize jump); progress indicator; multi-`{{ask}}` chaining.

---

## Stage 5 — Inverse capture hotkey

**Exit criterion:** select text anywhere → hotkey → a pre-filled "save as prompt" sheet writes a new markdown file.

- [ ] Capture hotkey + nonactivating save sheet (title field focused, body pre-filled).

---

## Stage 6 — Frecency + search

**Exit criterion:** ordering reflects what you actually use; only reach for FTS if in-memory filter
latency is *actually* felt (premature at <80 prompts).

- [ ] Usage-ranked ordering; FTS/SQLite only if/when latency demands (currently an **"ask first"** boundary).

---

## Stage 7 — Adaptive ⌥1–9 HUD row

**Exit criterion:** the row's positions are stable within an interaction and you trust ⌥3 to be ⌥3;
content adapts only between opens.

- [ ] Fixed 9 positions, content reorders by app/time, **no live reshuffle** (FEATURES §7).

---

## The real test (after Stage 1)

One week of daily personal use. If you reach for ⌥Space **reflexively**, it crossed over — that's
the only metric that ultimately matters.
