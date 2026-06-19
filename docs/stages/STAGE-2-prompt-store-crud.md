# Stage 2 — Prompt store + CRUD

**Status:** Pre-scaffold · **Depth:** tiered (intent + acceptance) · **Pulled by friction, not pre-built.**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-1](STAGE-1-mvp-palette.md) · → next [STAGE-3](STAGE-3-static-tokens.md)
Canonical: [PRD](../PRD.md) · [DESIGN](../DESIGN.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

In-app add/edit/delete, writing the **same markdown files** Stage 1 reads
([PRD §8](../PRD.md#8-staged-roadmap-at-a-glance)). No database — the file-per-prompt
store and live-reload already do the work; this just removes the text-editor hop.

**The feeling it protects** — Principle 4, *the library must fill itself*
([PRD §6](../PRD.md#6-principles)): adding/editing a prompt must stay painless.

## 2. Entry gate

[STAGE-1](STAGE-1-mvp-palette.md) shipped **and** hand-editing markdown finally got
annoying. That annoyance is the signal — not before
([TASKS Stage 2](../TASKS.md#stage-2--prompt-store--crud)).

## 3. Features in this stage

- In-app add / edit / delete writing the same markdown files. (No DB.)

## 4. UX

Tiered depth — acceptance only, no full pixel spec. Same focus-respecting,
Mattmode-Mono surface as the palette ([FEATURES §0](../FEATURES.md#0-visual-system--mattmode-mono)).
Spec the editing surface when this stage is actually pulled.

## 5. Design / mechanism

Builds directly on `PromptStore` + the markdown file shape
([DESIGN §7](../DESIGN.md#7-prompt-storage--markdown-file-per-prompt)): writes go to the
same `~/Prompts/` files; `DispatchSource` live-reload picks them up. The "DB only if ever
needed" boundary stays in force — adding SQLite/GRDB is **ask-first**
([CLAUDE.md Boundaries](../../CLAUDE.md)).

## 6. Tests for this stage

- **Tier A:** typecheck gate stays green; a write→reload round-trip over a temp
  `~/Prompts/` dir asserts an in-app edit produces a well-formed file the loader re-reads
  (parser/serializer symmetry).
- **Tier B (author):** add/edit/delete a real prompt from the UI and confirm it appears
  in the palette without hand-editing.

## 7. Build checklist

Canonical: [TASKS Stage 2](../TASKS.md#stage-2--prompt-store--crud).

- [ ] In-app add/edit/delete writing the same markdown files. (No DB.)

## 8. Exit criterion

Verbatim from [TASKS Stage 2](../TASKS.md#stage-2--prompt-store--crud):

> You can add/edit/delete a prompt without hand-editing a file — **and you wanted to,
> because hand-editing markdown finally got annoying** (that annoyance is the signal; not before).
