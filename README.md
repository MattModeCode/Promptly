# Prompt Palette

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

**Where am I?** → Gate 0: the paste-loop spike. The next checkbox is *extend `PasteProbe.swift`
with read-back verification + a per-target evidence dump, then run the 5-target matrix*. See
[docs/TASKS.md](docs/TASKS.md). Nothing app-side gets built until the spike is 5/5 green.

**How do I run it?**

```bash
# The spike (Apple Intel / x86_64). Click into a target field within the lead time:
arch -x86_64 swift PasteProbe.swift

# The app (once it exists): one command IS the whole dev loop — build, install, relaunch, tail log:
./run.sh
```

> Builds target **Apple Intel (x86_64)** — `arch -x86_64` for the spike, `ARCHS=x86_64` for the
> app. arm64/universal is an explicit future decision, not a default.

**Watch what the (invisible) paste loop is doing:**

```bash
log stream --predicate 'subsystem == "com.promptpalette"'   # AX status · strategy · paste result · clipboard restore
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
| [CLAUDE.md](CLAUDE.md) | Guidance for Claude Code + project boundaries + hazards. |

Full original vision/design doc:
`~/.gstack/projects/MattModeCode-ai-prompt-shortcut-app/mc-main-design-20260618-225221.md`

---

## Why native (not Electron/Tauri)

The never-steal-focus + paste-into-any-app bar can't be hit by a web stack — they fight the OS
for exactly those parts. This is native Swift / AppKit on purpose. See [docs/PRD.md](docs/PRD.md) → Non-goals.
