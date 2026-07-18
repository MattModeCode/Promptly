# FEATURE CATALOG — Promptly

**Status:** Stages 0–10 code-complete · **Audience:** the author (solo) · **Purpose:** the one map of the whole feature universe.

Sibling docs: [PRD.md](PRD.md) · [FEATURES.md](FEATURES.md) · [DESIGN.md](DESIGN.md) · [TASKS.md](TASKS.md) · root [README](../README.md)

---

## 1. How to read this

This is the **index**, not the spec. Every committed row is owned in depth by a
sibling doc (the **Owner** column). When this catalog and an owning doc disagree, **the owning
doc wins** — update the row, not the spec.

**Status legend**

| Tag | Meaning |
|-----|---------|
| **Committed** | On the stages 0–7 roadmap ([PRD §8](PRD.md#8-staged-roadmap-at-a-glance)). Has an owning doc and a stage file. |
| **Candidate** | Plausible future work, **not** committed. Lives in §3 with the friction that would pull it in. |
| **Non-goal** | Explicitly rejected for the foreseeable scope ([PRD §7](PRD.md#7-non-goals-explicit)). Listed so "we decided against it" is visible, not forgotten. |

Tokens (colors, type, spacing) are **single-sourced in [FEATURES §0](FEATURES.md#0-visual-system--mattmode-mono)** — this catalog links them, never re-lists values.

---

## 2. Committed features (stages 0–10)

### Stage 0 — Spike (the paste loop) · **HARD GATE**

| Feature | Owner | Notes |
|---------|-------|-------|
| Capture-before-present snapshot | DESIGN §1 (invariant 1) | Frontmost app captured before any panel exists. |
| Pid-targeted focused element (`copyFocusedElement(forPid:)`) | DESIGN §1 (inv. 2), TASKS Gate 0 [review D1] | Target the *captured* app, not system-wide / our own key panel. |
| Capability probe (B-vs-A from evidence) | DESIGN §2.2 | Decision table, not a fall-through. |
| Strategy B — AX direct write (selected-text / value-set) | DESIGN §2.2 | Build B **before** A on purpose. |
| Strategy A — clipboard + synthesized ⌘V | DESIGN §2.4 | `CGEvent`, keycode 9, `.maskCommand`. |
| Read-back verification (length-delta anchored) | DESIGN §2.1, TASKS Gate 0 [review A3] | Exit criterion is read-back, never `.success`. |
| Clobber ban (value-set only on empty field) | DESIGN §2.3 | HARD RULE. |
| Clipboard snapshot + restore (poll `changeCount`, ~120ms ceiling) | DESIGN §2.4 | HARD RULE: never leave clipboard mutated. |
| Per-target evidence dump | TASKS Gate 0 | Empirical basis for the §2.2 table. |
| Nonactivating KEY probe panel (`makeKeyProbePanel`) | TASKS Gate 0 [review D2] | Reproduces the app's real runtime focus condition. |
| 5-target cross-app matrix (Terminal/Safari/Xcode + VSCode/Notes) | TASKS Gate 0 | Tier B; human-run. |

### Stage 1 — MVP menu-bar palette

| Feature | Owner | Notes |
|---------|-------|-------|
| Menu-bar agent app (`LSUIElement`, status item) | DESIGN §5 | No Dock icon. |
| Build hygiene: ad-hoc sign, stable bundle ID, fixed path, native arm64, `run.sh` | DESIGN §4.1, §10 | From the first build — the TCC re-grant fix. |
| Global hotkey ⌥Space (Carbon, consumed, behind protocol) | DESIGN §3 | `HotkeyManager`. |
| Frontmost-app capture | DESIGN §1, §5 | `Capture` (invariant 1 in one place). |
| Nonactivating `NSPanel` + filter field + results list | DESIGN §5, FEATURES §1 | `PanelController`. |
| **Mattmode Mono visual system** (opaque dark, JetBrains Mono, 6px, no border) | FEATURES §0 | Tokens single-sourced in §0; **not** `NSVisualEffectView`. |
| Fixed-height 6-row scrolling viewport, clamp at full-list ends | FEATURES §1 | Scroll-past-6; no wrap. |
| Selected row: 2px silver left bar (primary signal) + faint fill | FEATURES §1 | The "whole game" peripheral glance. |
| Fuzzy filter (40ms debounce, in-memory) + matched-char emphasis | FEATURES §1/§2, DESIGN §6 | Sub-millisecond. |
| State A0 — empty library | FEATURES §2 | Distinct from no-match; points at "Open prompts folder…". |
| State A — recents default (top ~6 most-recently-used) | FEATURES §2, TASKS Stage 1 | Simple last-used timestamp, **not** Stage-6 frecency; cold launch → seed order. |
| State B — active filtering | FEATURES §2 | First match auto-selected each keystroke. |
| State C — no match (quiet line, no error color) | FEATURES §2 | — |
| State D — commit (≈80ms pulse → ≈120ms fade + 0.98 scale) | FEATURES §2, DESIGN §6 | Paste fires under the fade. |
| Persistent keyboard footer (A0/A/B/C) | FEATURES §2 | Drops only on State D. |
| Keyboard model (⌥Space / type / ↑↓ clamp / ↵ / esc) | FEATURES §6 | No wrap on ↑↓. |
| `PasteService` — spike extracted **verbatim** | DESIGN §5, CLAUDE.md Testability | Only module that must not drift. |
| `PromptStore` — markdown-per-file + `DispatchSource` live-reload | DESIGN §7 | No DB. |
| Markdown prompt file shape (frontmatter `name`/`keywords` + body) | DESIGN §7 | Fail loudly on load; dup `name` warns. |
| Silent success / loud failure (text left on clipboard) | FEATURES §3 | — |
| Lazy first-run Accessibility window (the one surface allowed to focus) | FEATURES §4, DESIGN §4 | Re-opens on each ungranted ⌥Space; single instance. |
| Dimmed/badged menu-bar icon when not granted | FEATURES §4/§5, DESIGN §4.1 | Persistent non-nagging reminder. |
| Menu-bar dropdown (AX status, hotkey rebind, open prompts folder, quit) | FEATURES §5 | The only "settings". |
| `os_log` four events (AX status, strategy, paste result, clipboard restore) | DESIGN §9 | `log stream` one-liner in README. |
| Seeded real library (8–10 genuine prompts + token cheatsheet) | TASKS Stage 1, PRD §5 | Cold-start that decides the week-long bet. |
| `PasteCore.swift` extraction + Tier A test suite | CLAUDE.md Test & Self-Heal Loop | One source of truth shared by spike + tests. |
| Palette accessibility (Reduce Motion / Increase Contrast / VoiceOver) | FEATURES §9, DESIGN §5/§6 | Accessibility setting wins on conflict. |
| Multi-monitor: panel on captured app's display | FEATURES §1, DESIGN §1 (inv. 4) | `present(captured:)` takes the screen. |

### Stage 2 — Prompt store + CRUD

| Feature | Owner | Notes |
|---------|-------|-------|
| In-app add/edit/delete writing the same markdown files | TASKS Stage 2, PRD §8 | No DB. Pulled when hand-editing gets annoying. |

### Stage 3 — Static tokens

| Feature | Owner | Notes |
|---------|-------|-------|
| `{{clipboard}}` / `{{date}}` substitution at paste time | DESIGN §8, FEATURES §7 | — |
| `{{cursor}}` placement (B-path precise, A-path caret-at-end) | DESIGN §2.5/§8 | Asymmetry documented now, implemented here. |
| Unknown tokens stay literal; empty known tokens log a warning | DESIGN §8 | Visible failure is how the grammar is learned. |

### Stage 4 — `{{ask:label}}` inline expansion

| Feature | Owner | Notes |
|---------|-------|-------|
| In-place fill-in transform (no panel move/resize) | FEATURES §7, TASKS Stage 4 | Same surface changes role; spatial trust. |
| ↵/Tab advance, esc cancels whole expansion, progress indicator | FEATURES §7 | Multi-`{{ask}}` chaining. |

### Stage 5 — Inverse capture

| Feature | Owner | Notes |
|---------|-------|-------|
| Capture hotkey → nonactivating "save as prompt" sheet (title empty, body pre-filled) | FEATURES §7, TASKS Stage 5 | ↵ writes a new markdown file; esc discards. |

### Stage 6 — Frecency + search

| Feature | Owner | Notes |
|---------|-------|-------|
| Usage-ranked (frecency) ordering | TASKS Stage 6, PRD §8 | Replaces Stage-1 recency. |
| FTS/SQLite — **ask-first boundary** | PRD §7, TASKS Stage 6, CLAUDE.md Boundaries | Only if in-memory latency is *actually* felt (premature <80 prompts). |

### Stage 7 — Adaptive ⌥1–9 HUD row

| Feature | Owner | Notes |
|---------|-------|-------|
| Fixed 9 positions; content reorders by app/time; no live reshuffle | FEATURES §7, TASKS Stage 7 | Number is the constant the hand learns. |
| Row reflow to add trailing ⌥-number chip column | FEATURES §1 | One-time geometry change (MVP collapses the chip column). |

### Stage 8 — Manual pinning + folders

| Feature | Owner | Notes |
|---------|-------|-------|
| Manual `pin:` / `description:` frontmatter | DESIGN §7, STAGE-8 | Hybrid over Stage-7 adaptive HUD: pins claim their slot first, frecency fills the rest; ⌥1–9 stay palette-only (no new hotkeys). |
| Folders as real subdirectories under `~/Prompts/` | DESIGN §7, STAGE-8 | Folder derived from parent dir, never frontmatter; recursive scan + `FSEventStream` watch replaces the old top-level `DispatchSource`. |
| Deterministic non-destructive pin-conflict resolution (`resolvePins`) | DESIGN §7, STAGE-8 | Lowest-`filename` winner; loser treated as unpinned for assignment, file left untouched (no silent rewrite). |
| Palette pinned chip styling (pin chip distinct from frecency chip) | FEATURES §1/§7, STAGE-8 | Draw-only: pinned chip shows even while filtering; no height/resize math touched. |

### Stage 9 — Three-pane Library window

| Feature | Owner | Notes |
|---------|-------|-------|
| Three-pane management window (sidebar / list / detail) | DESIGN §7, STAGE-9 | `NSSplitViewController`; its detail pane **replaces** the modal `PromptEditorPanel`. |
| Off-paste-path safety property | DESIGN §7, STAGE-9 | Never calls `Capture`/`present()`/`PasteService` — that's *why* it's allowed to take focus (the ⌥Space palette is untouched). |
| Folder create / move via the window | DESIGN §7, STAGE-9 | `PromptStore.move(_:toFolder:)` renames across dirs and migrates the usage key so frecency survives a reorganize. |

### Stage 10 — Library polish

| Feature | Owner | Notes |
|---------|-------|-------|
| Drag-to-move between sidebar folders | STAGE-10 | — |
| Folder rename (path rewrite + usage-key migration) | STAGE-10 | — |
| Inline pin-conflict warning UI | STAGE-10 | "⌥3 was on 'X' — moved here" on a user-initiated steal. |
| Relative-time usage display ("2h ago" / "3d ago") | STAGE-10 | Pure `RelativeTimeTests`-backed formatting on the `used N×` line. |

---

## 3. Candidate parking lot (not committed)

Each is deliberately **out** until a concrete friction pulls it in — consistent with
the docs' "let real use pull the stages" discipline. Rows marked **(currently a
non-goal)** are also in §4 / [PRD §7](PRD.md#7-non-goals-explicit); they are
"candidates with the bar set deliberately high," not omissions.

| Candidate | What would pull it in |
|-----------|------------------------|
| Import / export "prompt pack" | First time you want to move prompts between machines or share a set. |
| Prompt preview pane | A row's snippet stops being enough to tell two similar prompts apart before ↵. |
| Search/usage history view | You want to re-fire something you used yesterday but can't recall its name. |
| Typed / choice `{{ask}}` inputs (enum, date-picker) | Free-text `{{ask}}` (Stage 4) proves too loose for a recurring structured field. |
| Custom per-prompt hotkeys beyond ⌘1–9 | The 9-slot HUD row (Stage 7) fills and a 10th prompt earns a permanent key. |
| Prompt enable/disable (without deleting) | You want to mute a seasonal prompt without losing the file. |
| Prompts-folder backup / versioning (beyond git) | You edit destructively and want an in-app undo, not a `git checkout`. |
| Auto-update mechanism | The app is handed to a second person who won't run `run.sh`. |
| Onboarding tour | Same — a non-author user needs more than the lazy Accessibility window. |
| Usage analytics / telemetry | You want data to *tune* ordering — but note Principle 2 ("judgment not configurable"). |
| Light theme / theming | Mattmode Mono is **dark-only** today; a light-environment need would force the token set to fork. |
| iCloud / Git / cloud sync | *(currently a non-goal)* The visible local folder stops being a sufficient "sync". |
| Cross-platform (Windows/Linux/web) | *(currently a non-goal)* — would break the native never-steal-focus bar; effectively a different product. |
| SQLite / GRDB / FTS5 | *(ask-first)* In-memory filter latency is *actually* felt (premature <80 prompts) — this is the Stage 6 boundary. |
| arm64 / universal build | **Shipped** — ships native arm64 by default; the release build is Universal (arm64+x86_64). |
| Notarization / distribution tooling (Developer ID, `notarytool`, Homebrew cask) | *(currently a non-goal)* The app is actually handed to someone. |

---

## 4. Non-goals (canonical: [PRD §7](PRD.md#7-non-goals-explicit))

Mirrored here so the catalog is self-contained; **PRD §7 is canonical** — if these
drift, fix the mirror.

- **No tunable judgment.** No settings/preferences for the system's behavior — frecency/adaptive ordering stay non-configurable; the menu-bar dropdown holds the few real controls. (A management window for browsing/organizing/editing the library *is* in scope — it never pastes, so it can't threaten the half-second or focus.)
- **No cloud, no account, no sync** in the foreseeable scope. (A visible local prompt folder is the "sync.")
- **No cross-platform.** macOS only; native is required, not preferred.
- **No SQLite/GRDB/FTS5** until the library is large enough to actually need it (premature at <80 prompts).
- **Native arm64 by default; Universal (arm64+x86_64) on release.** *(Shipped — no longer a non-goal.)*
- **No notarization / distribution tooling** until the app is actually handed to someone.
