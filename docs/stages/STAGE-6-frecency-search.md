# Stage 6 — Frecency + search

**Status:** Pre-scaffold · **Depth:** tiered · **Carries an ask-first boundary (FTS/SQLite).**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-5](STAGE-5-inverse-capture.md) · → next [STAGE-7](STAGE-7-adaptive-hud-row.md)
Canonical: [PRD](../PRD.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

Ordering reflects what you **actually use** — usage-weighted *frecency* replacing Stage 1's
simple recency ([PRD §8](../PRD.md#8-staged-roadmap-at-a-glance)). FTS only once the library
is genuinely large.

**The feeling it protects** — Principle 2, *quiet and observant*
([PRD §6](../PRD.md#6-principles)): the system's *judgment* (ranking) is never user-tuned;
it just gets quietly better at predicting the next prompt.

## 2. Entry gate

[STAGE-1](STAGE-1-mvp-palette.md)'s recency ordering exists and is no longer good enough —
you reach for a prompt that should rank higher than it does.

## 3. Features in this stage

- Usage-ranked (frecency) ordering — replaces the last-used-timestamp recency.
- FTS/SQLite — **ask-first boundary**: only if in-memory filter latency is *actually* felt.

## 4. UX

No new surface — ordering changes underneath the existing State A / State B lists
([FEATURES §1/§2](../FEATURES.md#1-palette-anatomy-mvp)). Cold-start still falls back to
recency/seed order so a fresh history is never empty.

## 5. Design / mechanism

Replaces the Stage-1 ranking function inside `PromptStore`
([DESIGN §5](../DESIGN.md#5-mvp-module-decomposition)); the in-memory `[Prompt]` array and
fuzzy filter stay. **FTS5/SQLite/GRDB remains a hard ask-first boundary**
([PRD §7](../PRD.md#7-non-goals-explicit), [CLAUDE.md Boundaries](../../CLAUDE.md)) —
premature at <80 prompts; reach for it only when latency is measured and felt, not assumed.

## 6. Tests for this stage

- **Tier A:** frecency scoring as a pure function — given synthetic usage events
  (timestamps + counts), assert ordering matches the intended recency×frequency curve, and
  that a cold/empty history degrades to seed/recency order. No UI or DB.
- **Tier B (author):** over a week of real use, confirm the ordering tracks what you reach for.

## 7. Build checklist

Canonical: [TASKS Stage 6](../TASKS.md#stage-6--frecency--search).

- [ ] Usage-ranked ordering; FTS/SQLite only if/when latency demands (**ask-first**).

## 8. Exit criterion

Verbatim from [TASKS Stage 6](../TASKS.md#stage-6--frecency--search):

> Ordering reflects what you actually use; only reach for FTS if in-memory filter latency
> is *actually* felt (premature at <80 prompts).
