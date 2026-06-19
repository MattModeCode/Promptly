# AGENT WORKFLOW — building Promptly with subagents

**Status:** Pre-scaffold · **Audience:** the operator (author) driving Claude Code + subagents · **Binds to:** [CLAUDE.md → Test & Self-Heal Loop](../CLAUDE.md).

Sibling docs: [PRD.md](PRD.md) · [FEATURES.md](FEATURES.md) · [DESIGN.md](DESIGN.md) · [TASKS.md](TASKS.md) · [FEATURE-CATALOG.md](FEATURE-CATALOG.md) · [stages/](stages/)

This doc says **how** to use agents to build the app. The **what** lives in
[`stages/`](stages/); the **rules that gate** any agent's work live in
[CLAUDE.md](../CLAUDE.md). Where this doc and CLAUDE.md disagree, **CLAUDE.md wins**.

---

## 1. Core principle — one stage build-cell at a time

The product is "one risky loop, friction-pulled" ([DESIGN §1](DESIGN.md#1-the-one-risky-loop),
[TASKS](TASKS.md) preamble). The agent strategy mirrors it: **build one stage, prove it,
stop at the human gate.** No agent bulldozes stages 0→7 in a single run.

The matching **`stages/STAGE-N-*.md` file is the agent brief** — self-contained by design,
so a cell can start cold from one file plus the canonical docs it links. Hand a cell exactly
one stage; never "and also start the next one."

> **The hard rule, stated once:** an agent **never crosses a stage gate.** It gets a stage to
> green-on-its-runnable-tier and **prepares** the human gate; the author crosses it. For
> [Stage 0](stages/STAGE-0-spike.md) and every felt exit criterion ("reached for ⌥Space
> without thinking"), the gate is **physically agent-impassable** — it needs foreign-app
> focus, per-app TCC grants, or a human judgment an agent cannot make.

---

## 2. Roles in a build-cell

Spawn with the **Agent tool** (`subagent_type`) or the named gstack skill. Default cells are
**lean** — escalate only for the paste service (§4).

| Role | Agent type / skill | Job | Bounded by |
|------|--------------------|-----|-----------|
| **Architect** | `Plan` | Turn the stage file into a file-level implementation plan (which module, which functions, what to reuse). *Skip for trivial stages (2, 6).* | [DESIGN §5](DESIGN.md#5-mvp-module-decomposition) module decomposition |
| **Implementer** | `general-purpose` | Write the Swift for **only this stage**. Stage 0/1 paste code is **extracted verbatim** into `PasteCore.swift`, never reinvented. | [Boundaries](../CLAUDE.md): x86_64, native AppKit, **no deps without asking** |
| **Test engineer** | `general-purpose` | Write + run the stage's **Tier A** tests; on red, fix the *cause*. | [Honesty rules](../CLAUDE.md): never weaken an assertion; report which tier ran |
| **Code reviewer** | `/review` or `/code-review` (or `code-reviewer` agent) | Diff vs invariants: clobber ban, clipboard restore, capture-before-present, main-thread-only, pid-targeting. | [DESIGN §1–§2](DESIGN.md#1-the-one-risky-loop) invariants & hard rules |
| **Design reviewer** *(UI stages: 1, 4, 7)* | `/design-review` + `/browse` | Screenshot the running palette; compare to [`design/variant-B.html`](design/variant-B.html) + the Mattmode Mono tokens. | [FEATURES §0/§1/§2/§9](FEATURES.md#0-visual-system--mattmode-mono) |

**Default cell weight by stage:**

| Stage | Cell |
|-------|------|
| **0 (paste service)** | Implementer + **adversarial verification panel (§4)** + author-run Tier B. The risky one — escalate. |
| **1** | Architect + implementer + test engineer + code reviewer + **design reviewer**. The big one. |
| 3, 4, 5, 7 | Implementer + test engineer + 1 reviewer (design reviewer added for 4 & 7). |
| 2, 6 | Implementer + test engineer. (Skip the architect; small.) |

---

## 3. Per-stage orchestration

Default flow — **Agent tool**, sequential with parallel verification:

```
  Architect (Plan)  →  Implementer  →  [ Test engineer  ∥  Code reviewer ]  →  Design reviewer (UI stages)
        |                                          |
  stage file as brief                   Tier A green + honesty-clean
        └──────────  HUMAN GATE: Tier B matrix + felt exit criterion (author only)  ──────────┘
```

- **Test engineer and code reviewer run in parallel** — they don't depend on each other; both
  consume the implementer's diff.
- The **human gate is the barrier between stages.** An agent's deliverable for a stage is:
  code in, **Tier A green**, **Tier B steps written out for the author**, and an explicit
  *"this stage is NOT certified — Tier B / the felt criterion is yours."*
- **Agent teams option:** keep one **named, persistent reviewer** (e.g. spawn with
  `name: "PasteGuard"`) alive across stages via SendMessage, so invariant-continuity carries
  forward instead of being re-derived cold in each cell. Useful for the paste-path invariants
  that recur in Stages 0, 1, 3.
- **Workflow option:** the same pipeline can be encoded deterministically with the Workflow
  tool (architect → implement → verify per stage). That needs **explicit opt-in** ("use a
  workflow"); the default here is the Agent-tool cell above.

---

## 4. Paste-service escalation (Stage 0 and any change to `PasteCore`)

The paste loop is the one place a plausible-but-wrong "it works" is catastrophic (silent
clobber, lost clipboard). For Stage 0 and any later diff touching `PasteCore.swift`, escalate
verification beyond a single reviewer:

- Spawn **2–3 independent reviewers**, each prompted to **refute**, not confirm:
  - *"Refute that read-back actually proves the paste landed"* (hunt for the
    `.success`-but-no-op / false-positive `contains()` path — [DESIGN §2.1](DESIGN.md#21-verify-by-read-back-not-by-return-code),
    [TASKS review A3](TASKS.md#-gate-0--the-spike-nothing-past-this-line-until-55-green)).
  - *"Refute that the clipboard is byte-identical after a Strategy A paste"* (race under
    app-switch, types not restored — [DESIGN §2.4](DESIGN.md#24-strategy-a--clipboard--synthesized-v)).
  - *"Refute that we never value-set a non-empty field"* (clobber-ban branch —
    [DESIGN §2.3](DESIGN.md#23-clobber-ban-hard-rule)).
- **Kill the claim on majority refute.** Only when the refuters fail to break it does the
  Tier A result stand — and even then, **Gate 0 is not green until the author runs Tier B**.

This adversarial pass is **reserved for the paste service**. Lighter stages get a single
reviewer (§2).

---

## 5. Per-stage runbook (paste this to kick a cell)

> Read `docs/stages/STAGE-<N>-<slug>.md` and the canonical sections it links. Implement
> **only this stage** — do not touch later stages or refactor unrelated code. Reuse the
> modules named in DESIGN §5; for any paste behavior, extract/keep `PasteCore.swift` as the
> single source of truth and do not reinvent it. Keep **Tier A green** (CLAUDE.md → Test &
> Self-Heal Loop) and obey the **honesty rules** — never weaken or delete an assertion to go
> green; a read-back miss or non-clean clipboard is a real bug to fix at the cause. Adding any
> dependency, SQLite/GRDB/FTS5, or changing the hotkey mechanism is **ask-first** — stop and
> ask. When done, report **which tier actually ran**, write out the **Tier B** steps for me to
> run, and state plainly that the stage is **not certified** until I run Tier B and feel the
> exit criterion. **Never claim a gate green from Tier A alone.**

For [Stage 0](stages/STAGE-0-spike.md), append: *"Also run the §4 adversarial refutation panel
before reporting."*

---

## 6. The binding contract

These are not suggestions — they are the [CLAUDE.md](../CLAUDE.md) rules every cell inherits:

1. **Tier A / Tier B split** — agents run Tier A; only the author runs the cross-app matrix and
   certifies a gate. **Never claim Gate 0 green from Tier A alone.**
2. **Honesty rules** — never weaken/delete an assertion; never leave the clipboard mutated;
   never value-set a non-empty field. A test that "passes" by violating either is a regression.
3. **One source of truth for paste** — `PasteService`/tests extract `PasteCore` verbatim; they
   must not drift from the proven spike ([DESIGN §5](DESIGN.md#5-mvp-module-decomposition)).
4. **Ask-first boundaries** — dependencies, SQLite/GRDB/FTS5, hotkey-mechanism changes
   ([CLAUDE.md Boundaries](../CLAUDE.md)).
5. **One stage at a time; never cross a gate.**
