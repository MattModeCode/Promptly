# Stage 7 — Adaptive ⌥1–9 HUD row

**Status:** Pre-scaffold · **Depth:** tiered · **"A keyboard, not a piano."**

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · ← prev [STAGE-6](STAGE-6-frecency-search.md)
Canonical: [FEATURES](../FEATURES.md) · [TASKS](../TASKS.md)

> Assembled execution view; **reference, don't duplicate.**

---

## 1. Intent

A heads-up display, not a menu: **fixed 9 positions, always in the same place; only the
*content* reorders** by app/time-of-day ([PRD §8](../PRD.md#8-staged-roadmap-at-a-glance)).
The number is the constant the hand learns; the label under it changes.

**The feeling it protects:** the hand trusts ⌥3 to be ⌥3 — muscle memory over a menu.

## 2. Entry gate

[STAGE-6](STAGE-6-frecency-search.md)'s adaptive ordering exists (the HUD row needs a
ranking to decide which prompt sits at each position).

## 3. Features in this stage

- Fixed 9 positions; content reorders by app/time; **no live reshuffle** — re-sort only
  between opens; positions freeze for the duration of any single appearance.
- Row reflow to introduce the trailing **⌥-number chip column** (MVP collapses it).

## 4. UX

[FEATURES §7 → Stage 7](../FEATURES.md#7-later-stages--tiered-depth-intent--key-decisions)
(the thin-strip mockup) and the chip-column reflow noted in
[FEATURES §1 → Row design](../FEATURES.md#row-design--one-prompt-per-row-title-forward) —
called out there as an *expected* one-time geometry change, not a surprise reshuffle.

## 5. Design / mechanism

Extends `PanelController`'s row layout ([DESIGN §5](../DESIGN.md#5-mvp-module-decomposition))
with the trailing number column, and binds ⌥1–9 to the current position assignment. The
**freeze-positions-within-an-appearance** rule is the load-bearing constraint — assignment
is computed at present-time (like the screen in invariant 4) and held constant until dismiss.

## 6. Tests for this stage

- **Tier A:** position-assignment as a pure function — given context (app/time) + ranking,
  assert the 9 slots fill deterministically and that **assignment is stable across a single
  appearance** (same input → same map; no reshuffle until a new open). No UI needed.
- **Tier B (author):** confirm ⌥3 fires the same prompt for the whole time the row is up,
  and that re-sorting only happens between opens.

## 7. Build checklist

Canonical: [TASKS Stage 7](../TASKS.md#stage-7--adaptive-19-hud-row).

- [ ] Fixed 9 positions, content reorders by app/time, **no live reshuffle**.

## 8. Exit criterion

Verbatim from [TASKS Stage 7](../TASKS.md#stage-7--adaptive-19-hud-row):

> The row's positions are stable within an interaction and you trust ⌥3 to be ⌥3; content
> adapts only between opens.
