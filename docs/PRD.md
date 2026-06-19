# PRD — Promptly

**Status:** Pre-scaffold · **Audience:** the author (solo) · **Platform:** macOS, native Swift/AppKit, Apple Intel (x86_64)

Sibling docs: [FEATURES.md](FEATURES.md) · [DESIGN.md](DESIGN.md) · [TASKS.md](TASKS.md) · [FEATURE-CATALOG.md](FEATURE-CATALOG.md) · [stages/](stages/) · [AGENT-WORKFLOW.md](AGENT-WORKFLOW.md) · root [README](../README.md)

---

## 1. The one-sentence product

A global macOS prompt launcher: in any text field you hit **⌥Space** without looking, type a
fragment, the right template is already highlighted, hit **↵**, and the fully-assembled prompt
drops into the field with your cursor where it should be — in ~700ms, with focus never leaving
the app you're in.

## 2. The problem

The prompt-tool category is full of apps that make you *go somewhere* to get your prompt — open
a window, find the entry, copy it, switch back, paste, fix the cursor. Every one of those steps
is a context switch, and context switches are where the "I'll just write it by hand" instinct
wins. The result: prompt libraries that get built once and die, because *using* them is slower
than not.

The cool version inverts it: **the prompt comes to you.** No window to visit, no mode to enter,
no focus stolen. The tool is invisible until the half-second you need it, then invisible again.

## 3. The target feeling (the real spec)

The product is not a feature list — it's a feeling, and the engineering exists to protect it:

> The half-second where you hit ↵ and start reading the result **before you consciously decided
> which prompt you wanted** — when it crosses from "a tool I use" to "a thing my hands know."

Everything technical (the ~40ms debounce, the sub-millisecond in-memory filter, the ~120ms
fade, capturing the frontmost app *before* the panel appears) is in service of that half-second.
If a decision doesn't protect it, it's wrong.

## 4. Who it's for

The author, first. This is a solo side project built for daily personal use. "Shareable" is a
later, explicit decision (see Non-goals and DESIGN.md → Distribution). Designing for an
imaginary general user now would add weight that fights the feeling.

## 5. Success criteria

| Gate | Definition |
|------|------------|
| **Spike (hard gate)** | `PasteProbe.swift` lands its marker in the **3 must-pass apps** (Terminal, Safari, Xcode) **confirmed by AX read-back**, clipboard **byte-identical** after each. The **2 known-hostile apps** (VSCode/Electron, Notes/sandboxed) must reach at least a **clean-clipboard clipboard-fallback** paste; their AX-write outcome is recorded as a known limitation, not a blocker. A silent failure that *clobbers or loses clipboard contents* blocks regardless of tier. Nothing app-side is built until this is green. (See TASKS §Gate 0 for the tiering rationale.) |
| **MVP** | ⌥Space → nonactivating palette → fuzzy filter over an in-memory prompt list → ↵ pastes the prompt into the frontmost app, cursor correct, panel gone, ~700ms, **focus never stolen**. |
| **Crossed over** | Within a week of daily use, you reach for ⌥Space **without thinking**. This is the only success metric that ultimately matters. *Precondition: the MVP ships with a **real seeded library (8–10 prompts you genuinely use)**, not placeholders — a thin library never becomes a reflex and the bet never gets a fair test (see TASKS §Stage 1).* |

## 6. Principles

1. **Protect the half-second.** Latency and focus are the product. Features that threaten either lose.
2. **Quiet and observant, not configurable.** No settings *window*. The system's *judgment*
   (frecency, adaptive ordering) is never tuned by the user; the system's *plumbing*
   (Accessibility status, hotkey rebind) is inspectable via the menu-bar dropdown.
3. **Silence on success, one honest line on failure.** A successful paste needs no confirmation —
   the text appearing *is* the confirmation. A *failed* paste must never look like nothing happened.
4. **The library must fill itself.** Most prompt tools die because adding prompts is a chore.
   Hand-editing must be painless (markdown files, live-reload) and later an inverse-capture
   hotkey turns real work into prompts as a byproduct.
5. **Prove the risk before building around it.** The whole product is one paste loop; it gets
   spiked in ~80 lines before any UI or store exists.

## 7. Non-goals (explicit)

- **No settings panel / preferences window.** (Menu-bar dropdown holds the few real controls only.)
- **No cloud, no account, no sync** in the foreseeable scope. (A visible local prompt folder is the "sync.")
- **No cross-platform.** macOS only; native is required, not preferred — Electron/Tauri can't hit
  the never-steal-focus + paste-into-any-app bar.
- **No SQLite/GRDB/FTS5** until the library is large enough to actually need it (premature at <80 prompts).
- **No arm64/universal build** yet. x86_64 is the floor; universal is a future decision.
- **No notarization / distribution tooling** until the app is actually handed to someone.

## 8. Staged roadmap (at a glance)

Specified at **tiered depth**: the spike + MVP deeply (see FEATURES/DESIGN/TASKS); stages 3–8 as
intent + rough acceptance criteria + open questions, to be pulled by real friction, not pre-built.

| # | Stage | One-line intent | Stage file |
|---|-------|-----------------|------------|
| 0 | **Spike** | Prove the paste loop in `PasteProbe.swift` across 5 targets. **Gate.** | [STAGE-0](stages/STAGE-0-spike.md) |
| 1 | **MVP palette** | ⌥Space → nonactivating panel → fuzzy filter → ↵ paste. Markdown-file prompts + live-reload. | [STAGE-1](stages/STAGE-1-mvp-palette.md) |
| 2 | **Prompt store + CRUD** | In-app add/edit/delete (markdown files first; DB only if ever needed). | [STAGE-2](stages/STAGE-2-prompt-store-crud.md) |
| 3 | **Static tokens** | `{{clipboard}}`, `{{date}}`, `{{cursor}}` (cursor is B-path-precise; see DESIGN). | [STAGE-3](stages/STAGE-3-static-tokens.md) |
| 4 | **`{{ask:label}}`** | Palette expands inline into a tiny fill-in field instead of paste-and-close. | [STAGE-4](stages/STAGE-4-ask-inline-expansion.md) |
| 5 | **Inverse capture** | Select text anywhere → hotkey → minimal "save as prompt" sheet, pre-filled. | [STAGE-5](stages/STAGE-5-inverse-capture.md) |
| 6 | **Frecency + search** | Usage-ranked ordering; FTS only once the library is large. | [STAGE-6](stages/STAGE-6-frecency-search.md) |
| 7 | **Adaptive ⌥1–9 row** | A heads-up display, not a menu: fixed positions, content reorders by app/time. | [STAGE-7](stages/STAGE-7-adaptive-hud-row.md) |

Each stage's exit criterion authorizes the next; see [TASKS.md](TASKS.md). The full feature
universe (incl. candidates + non-goals) is indexed in [FEATURE-CATALOG.md](FEATURE-CATALOG.md);
how to build each stage with subagents is in [AGENT-WORKFLOW.md](AGENT-WORKFLOW.md).

## 9. Validation provenance

This PRD and its sibling docs are the consolidated output of an office-hours design session
plus three parallel specialist reviews (design, engineering, developer-experience), a
CEO/scope review (HOLD-SCOPE rigor — folded in: tiered spike gate, recency-vs-frecency
cold-start fix, seed-a-real-library as a Stage-1 exit condition), and the author's decisions.
The full original vision lives in the design doc referenced in [DESIGN.md](DESIGN.md) → Deeper Context.
