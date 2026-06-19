# Stage 0 — Spike: prove the paste loop · **HARD GATE**

**Status:** Pre-scaffold · **Tier:** mostly human-run (Tier B) · **Gate:** nothing app-side is built until this is green.

↑ [FEATURE-CATALOG](../FEATURE-CATALOG.md) · → next [STAGE-1](STAGE-1-mvp-palette.md)
Canonical: [PRD](../PRD.md) · [FEATURES](../FEATURES.md) · [DESIGN](../DESIGN.md) · [TASKS](../TASKS.md) · [CLAUDE.md](../../CLAUDE.md) Test & Self-Heal Loop

> This file assembles one stage for execution. The load-bearing detail lives in the
> canonical docs (linked per section); read those for the full text. Do not duplicate
> spec here — **reference it.**

---

## 1. Intent

Prove the one risky loop in `PasteProbe.swift` across 5 target apps before any UI or
store exists. The whole product is this loop ([DESIGN §1](../DESIGN.md#1-the-one-risky-loop));
everything else is toppings on a pizza you haven't proven you can bake.

**The feeling it protects** ([PRD §3](../PRD.md#3-the-target-feeling-the-real-spec)):
that the assembled text lands in the host app, cursor right, clipboard untouched —
the silent reliability the half-second is built on.

## 2. Entry gate

Nothing precedes this. `PasteProbe.swift` exists and typechecks for x86_64.

## 3. Features in this stage

(From [FEATURE-CATALOG §2 → Stage 0](../FEATURE-CATALOG.md#stage-0--spike-the-paste-loop--hard-gate--stage-file).)

- Capture-before-present snapshot (invariant 1).
- Pid-targeted focused element — `copyFocusedElement(forPid:)` (invariant 2).
- Capability probe (B-vs-A from evidence).
- Strategy B (AX direct write) — built **before** A on purpose.
- Strategy A (clipboard + synthesized ⌘V).
- Read-back verification, anchored on the length delta.
- Clobber ban; clipboard snapshot + restore (poll `changeCount`).
- Per-target evidence dump; nonactivating KEY probe panel.
- 5-target cross-app matrix.

## 4. UX

None. The spike is a CLI tool with no panel UI — it logs and dumps evidence. Palette
UX begins in [STAGE-1](STAGE-1-mvp-palette.md).

## 5. Design / mechanism

- **The loop + invariants:** [DESIGN §1](../DESIGN.md#1-the-one-risky-loop) — esp.
  inv. 1 *capture-before-present* and inv. 2 *paste-targets-captured-app*.
- **Verify by read-back, not return code:** [DESIGN §2.1](../DESIGN.md#21-verify-by-read-back-not-by-return-code).
  An AX `set` returning `.success` from an Electron/WebKit shim that no-ops is the
  exact failure this project exists to catch.
- **Capability-probe decision table:** [DESIGN §2.2](../DESIGN.md#22-b-vs-a-is-a-capability-probe-not-a-fall-through).
- **Clobber ban (HARD RULE):** [DESIGN §2.3](../DESIGN.md#23-clobber-ban-hard-rule) —
  value-set only when read-back confirms the field was empty.
- **Strategy A + clipboard restore (HARD RULE):** [DESIGN §2.4](../DESIGN.md#24-strategy-a--clipboard--synthesized-v) —
  poll `NSPasteboard.changeCount`; restore must survive an app-switch mid-paste.
- **`{{cursor}}` asymmetry** (document now, implement Stage 3): [DESIGN §2.5](../DESIGN.md#25-cursor-asymmetry-document-now-implement-in-stage-3).

The spike's hardening (already done — see [TASKS Gate 0](../TASKS.md#-gate-0--the-spike-nothing-past-this-line-until-55-green)
checkboxes): `copyFocusedElement(forPid:)` [review D1], `makeKeyProbePanel` [review D2],
length-delta `ReadBack` [review A3].

## 6. Tests for this stage

Per [CLAUDE.md → Test & Self-Heal Loop](../../CLAUDE.md):

- **Tier A (agent-runnable today):** the typecheck gate —
  `arch -x86_64 swiftc -typecheck PasteProbe.swift` must exit 0. The clipboard
  round-trip, decision-table, and in-process read-back checks **activate in Stage 1**
  once `PasteCore.swift` is extracted (they need the pure logic split out).
- **Tier B (human-only):** the **5-target matrix** below. An agent can neither focus
  foreign apps nor approve TCC — it prepares the steps; the author runs them.

## 7. Build checklist

Mirrors [TASKS Gate 0](../TASKS.md#-gate-0--the-spike-nothing-past-this-line-until-55-green) — that file is canonical for `[x]/[ ]` state.

- [x] Read-back verification after each attempt (B and A).
- [x] Per-target evidence dump.
- [x] [review D1] pid-targeted focused element.
- [x] [review D2] nonactivating KEY probe panel.
- [x] [review A3] length-delta-anchored read-back.
- [ ] Run the matrix (author): `arch -x86_64 swift PasteProbe.swift`, click into each app within the lead time, grant Accessibility to Terminal.

**Matrix** (Tier B; author runs):

| Target | Engine / failure mode | Tier |
|--------|-----------------------|------|
| Terminal | native AppKit + self-paste | **must-pass** |
| Safari | WebKit text fields | **must-pass** |
| Xcode | Apple text engine | **must-pass** |
| VSCode | Electron | known-hostile |
| Notes | sandboxed | known-hostile |

## 8. Exit criterion — **HARD GATE**

Verbatim from [TASKS Gate 0](../TASKS.md#-gate-0--the-spike-nothing-past-this-line-until-55-green):

> **All 3 must-pass targets confirmed by read-back AND clipboard byte-identical before ANY app code.**
> The two known-hostile targets must reach **at least the clipboard fallback (A) with a clean clipboard**;
> a silent read-back failure that also clobbers or loses clipboard contents still blocks.

**An agent must never mark this gate green from Tier A alone** — the must-pass
criterion is read-back confirmed in *real* apps, which only Tier B proves
([CLAUDE.md honesty rules](../../CLAUDE.md)).
