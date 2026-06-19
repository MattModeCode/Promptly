# Stage 4 — `{{ask:label}}` inline expansion

**Status:** Pre-scaffold · **Depth:** tiered · **Highest-value, highest-risk later UX.**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-3](STAGE-3-static-tokens.md) · → next [STAGE-5](STAGE-5-inverse-capture.md)
Canonical: [FEATURES](../FEATURES.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

On ↵, instead of paste-and-close, the palette **transforms in place** into a minimal
fill-in flow: the search field becomes the answer field, the label is the placeholder,
↵ advances to the next `{{ask}}` or fires the paste on the last
([PRD §8](../PRD.md#8-staged-roadmap-at-a-glance)).

**The feeling it protects:** spatial trust — the hand has learned where the panel lives;
filling in a value must not move it.

## 2. Entry gate

[STAGE-3](STAGE-3-static-tokens.md) shipped (token grammar exists; `{{ask:label}}` extends it).

## 3. Features in this stage

- In-place fill-in transform — **same surface changes role; the panel must not move or resize jarringly**.
- ↵/Tab advance; esc cancels the *whole* expansion; quiet progress indicator ("1 of 3" / dots).
- Multi-`{{ask}}` chaining.

## 4. UX

[FEATURES §7 → Stage 4](../FEATURES.md#7-later-stages--tiered-depth-intent--key-decisions),
which carries the ASCII transform mockup. **Critical rule** (repeated because it's the
whole risk): preserve the panel's position and size; only the field's role changes.

## 5. Design / mechanism

Extends the token pipeline ([DESIGN §8](../DESIGN.md#8-token-grammar)): `{{ask:label}}`
tokens are resolved *interactively before* the final substitution+paste, rather than from
context. The transform reuses the existing `PanelController` surface — no new window — so
invariant discipline and the Mattmode-Mono surface carry over unchanged. Spec the state
machine (which token is active, advance/cancel) when the stage is pulled.

## 6. Tests for this stage

- **Tier A:** the ask-resolution state machine as a pure model — N `{{ask}}` tokens
  advance in order, Tab and ↵ both advance, esc resets, the final substitution composes
  collected answers correctly. No UI needed for the model tests.
- **Tier B (author):** run a 2–3 `{{ask}}` prompt end-to-end and confirm the panel never
  jumps and esc cancels cleanly mid-flow.

## 7. Build checklist

Canonical: [TASKS Stage 4](../TASKS.md#stage-4--asklabel-inline-expansion).

- [ ] In-place transform (no resize jump); progress indicator; multi-`{{ask}}` chaining.

## 8. Exit criterion

Verbatim from [TASKS Stage 4](../TASKS.md#stage-4--asklabel-inline-expansion):

> A `{{ask}}` prompt expands the palette in place into a fill-in flow without the panel
> jumping; ↵/Tab advance, esc cancels the whole expansion.
