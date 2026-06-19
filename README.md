# Promptly

A native macOS prompt launcher that comes to *you*. Hit **⌥Space** in any text field, type a
fragment, the right template is already highlighted, hit **↵**, and the fully-assembled prompt
drops into the field with your cursor where it should be — in ~700ms, **focus never stolen**.

No window to visit, no mode to enter. The tool is invisible until the half-second you need it,
then invisible again. The proof it's working: within a week you reach for ⌥Space without thinking.

```
   ⌥Space ┌──────────────────────────────────────────────┐
   ───────▶│  pr                                          │
          ├──────────────────────────────────────────────┤
          │ ▸ PR description     summarize the diff, risk…│  ← ↵ pastes this into the app you were in
          │   Bug report triage  file a structured bug …  │
          └──────────────────────────────────────────────┘
```

> **Status:** pre-scaffold. The paste-loop spike (`PasteProbe.swift`) exists; the menu-bar app
> does not yet. This README describes where the project is going and how to work on it today.

---

## For developers (working on this today)

**Where am I?** → Gate 0: the paste-loop spike. The spike is **already extended** (read-back
verification + per-target evidence dump are done — see the `[x]` boxes in [docs/TASKS.md](docs/TASKS.md)).
The next checkbox is the **manual 5-target matrix run**: `arch -x86_64 swift PasteProbe.swift`,
click into each target within the 4-second countdown, and paste each evidence row the probe prints
into TASKS §Gate 0. Nothing app-side gets built until the spike is 5/5 green.

**How do I run it?**

```bash
# The spike (Apple Intel / x86_64) — the one thing that runs today. It counts down 4s,
# then probes; click into a target field before it fires:
arch -x86_64 swift PasteProbe.swift
```

> **`run.sh` does not exist yet.** It's a Stage-1 deliverable (build → install → relaunch →
> tail log) — see [docs/TASKS.md](docs/TASKS.md) Stage 1. Once the app target exists, `./run.sh`
> becomes the whole dev loop and THE command in this section. Until then, the spike above is it.

> Builds target **Apple Intel (x86_64)** — `arch -x86_64` for the spike, `ARCHS=x86_64` for the
> app. arm64/universal is an explicit future decision, not a default.

**Watch what the (invisible) paste loop is doing:**

```bash
log stream --predicate 'subsystem == "com.promptly"'   # AX status · strategy · paste result · clipboard restore
```

**What will bite you** (full list in [CLAUDE.md](CLAUDE.md) → *Things That Will Bite You*):
- **Accessibility permission is a silent-failure point**, and a rebuild can *silently revoke* it —
  which looks exactly like "the paste loop broke." The fix (stable bundle ID + ad-hoc signing +
  fixed install path) is baked into `run.sh`; if it ever gets confused: `tccutil reset Accessibility <bundle-id>`.
- The spike grants **Terminal**; the app grants the **bundle** — the grant does **not** transfer.
- Capture the frontmost app *before* showing the panel, or you paste into your own panel.

**Where's the deep context?**

| Doc | What's in it |
|-----|--------------|
| [docs/PRD.md](docs/PRD.md) | The product, the target feeling, success criteria, non-goals, roadmap. |
| [docs/FEATURES.md](docs/FEATURES.md) | UX/interaction spec + ASCII mockups of every palette state. |
| [docs/DESIGN.md](docs/DESIGN.md) | Technical design: the paste loop, paste service, hotkey, permissions, modules. |
| [docs/TASKS.md](docs/TASKS.md) | Gated build checklist (the spike is the gate). |
| [docs/FEATURE-CATALOG.md](docs/FEATURE-CATALOG.md) | The whole feature universe in one index — committed / candidate / non-goal. |
| [docs/stages/](docs/stages/) | Per-stage execution files (one self-contained brief per roadmap stage). |
| [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md) | How to build each stage with subagents (gate-aware, Tier A/B-bound). |
| [CLAUDE.md](CLAUDE.md) | Guidance for Claude Code + project boundaries + hazards. |

Full original vision/design doc:
`~/.gstack/projects/MattModeCode-ai-prompt-shortcut-app/mc-main-design-20260618-225221.md`

---

## Why native (not Electron/Tauri)

The never-steal-focus + paste-into-any-app bar can't be hit by a web stack — they fight the OS
for exactly those parts. This is native Swift / AppKit on purpose. See [docs/PRD.md](docs/PRD.md) → Non-goals.
