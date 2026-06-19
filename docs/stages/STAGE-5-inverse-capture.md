# Stage 5 — Inverse capture hotkey

**Status:** Pre-scaffold · **Depth:** tiered (acceptance criteria only) · **Pulled by friction.**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-4](STAGE-4-ask-inline-expansion.md) · → next [STAGE-6](STAGE-6-frecency-search.md)
Canonical: [FEATURES](../FEATURES.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

Select text anywhere → capture hotkey → a minimal "save as prompt" sheet, pre-filled with
the captured text as the body ([PRD §8](../PRD.md#8-staged-roadmap-at-a-glance)). The
library fills itself as a byproduct of real work.

**The feeling it protects** — Principle 4, *the library must fill itself*
([PRD §6](../PRD.md#6-principles)): turning real work into prompts must cost almost nothing.

## 2. Entry gate

[STAGE-1](STAGE-1-mvp-palette.md) shipped (this reuses the capture + nonactivating-surface
machinery). Naturally lands after Stage 2's CRUD makes prompts first-class.

## 3. Features in this stage

- A second **capture hotkey** + a nonactivating "save as prompt" sheet: title field
  focused (the one thing you must supply), body pre-filled with the selection.
- ↵ saves a new markdown file; esc discards.

## 4. UX

[FEATURES §7 → Stage 5](../FEATURES.md#7-later-stages--tiered-depth-intent--key-decisions).
Same focus-respecting discipline as the palette; hint that dynamic bits could later become
`{{tokens}}`. Acceptance-criteria depth only at this stage.

## 5. Design / mechanism

Reuses `Capture` + the nonactivating-panel pattern ([DESIGN §1](../DESIGN.md#1-the-one-risky-loop),
[§5](../DESIGN.md#5-mvp-module-decomposition)) and writes through the same markdown file
shape ([DESIGN §7](../DESIGN.md#7-prompt-storage--markdown-file-per-prompt)) — live-reload
makes the new prompt appear in the palette immediately. A **second** Carbon hotkey
registration via `HotkeyManager`; changing the hotkey mechanism stays **ask-first**
([CLAUDE.md Boundaries](../../CLAUDE.md)).

## 6. Tests for this stage

- **Tier A:** the sheet's save path produces a well-formed markdown file (frontmatter +
  body) that `PromptStore` re-reads — the same parser/serializer symmetry as Stage 2,
  over a temp dir. Capturing the selection is Tier B (needs a foreign app).
- **Tier B (author):** select text in a real app, fire the capture hotkey, confirm the
  sheet pre-fills, save, and the new prompt is searchable in the palette.

## 7. Build checklist

Canonical: [TASKS Stage 5](../TASKS.md#stage-5--inverse-capture-hotkey).

- [ ] Capture hotkey + nonactivating save sheet (title focused, body pre-filled).

## 8. Exit criterion

Verbatim from [TASKS Stage 5](../TASKS.md#stage-5--inverse-capture-hotkey):

> Select text anywhere → hotkey → a pre-filled "save as prompt" sheet writes a new markdown file.
