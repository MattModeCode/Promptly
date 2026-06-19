# Stage 3 — Static tokens

**Status:** Pre-scaffold · **Depth:** tiered (intent + key decisions) · **Pulled by friction.**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-2](STAGE-2-prompt-store-crud.md) · → next [STAGE-4](STAGE-4-ask-inline-expansion.md)
Canonical: [FEATURES](../FEATURES.md) · [DESIGN](../DESIGN.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

Substitute `{{clipboard}}`, `{{date}}`, `{{cursor}}` at paste time
([PRD §8](../PRD.md#8-staged-roadmap-at-a-glance)). The prompt stops being static text
and starts assembling from context — the first real "assembled prompt" the product name promises.

## 2. Entry gate

[STAGE-1](STAGE-1-mvp-palette.md) shipped. (Tokens ride on the proven paste path; `{{cursor}}`
in particular depends on the B-vs-A capability split being real.)

## 3. Features in this stage

- `{{clipboard}}` / `{{date}}` substitution at paste time.
- `{{cursor}}` placement — **precise on the B path, caret-at-end on the A fallback**.
- Unknown tokens stay literal; empty known tokens log a warning.

## 4. UX

[FEATURES §7 → Stage 3](../FEATURES.md#7-later-stages--tiered-depth-intent--key-decisions).
Discoverability without a settings panel: the seed **"token cheatsheet"** prompt (shipped
in Stage 1) + a header comment block in the prompt files. A typo'd `{{clipboaord}}` pastes
verbatim so the mistake is visible — there is no help panel.

## 5. Design / mechanism

- **Token grammar:** [DESIGN §8](../DESIGN.md#8-token-grammar) — `{{token}}` syntax;
  unknown stays literal; empty known substitutes empty with a logged warning.
- **`{{cursor}}` asymmetry:** [DESIGN §2.5](../DESIGN.md#25-cursor-asymmetry-document-now-implement-in-stage-3) —
  B path can set `kAXSelectedTextRange` after insert; A path's synthesized ⌘V leaves the
  caret at end. **Stage 3 must not promise placement the fallback can't honor.**

## 6. Tests for this stage

- **Tier A:** token-expansion unit tests — `{{date}}` formats correctly, `{{clipboard}}`
  pulls the snapshot, unknown tokens pass through verbatim, empty known logs (not crashes).
  `{{cursor}}` resolves to a B-path range index vs an A-path end-of-text marker per the
  asymmetry. Pure-function tests; no foreign app needed.
- **Tier B (author):** paste a `{{clipboard}}`/`{{date}}` prompt into a real app and
  confirm assembly + caret position on both a B-path and an A-path target.

## 7. Build checklist

Canonical: [TASKS Stage 3](../TASKS.md#stage-3--static-tokens).

- [ ] `{{clipboard}}`, `{{date}}`, `{{cursor}}` (cursor precise on B, caret-at-end on A).
- [ ] Unknown tokens stay literal; empty known tokens log a warning.

## 8. Exit criterion

Verbatim from [TASKS Stage 3](../TASKS.md#stage-3--static-tokens):

> A prompt with `{{clipboard}}`/`{{date}}` assembles correctly at paste time.
