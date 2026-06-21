# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Promptly** — a native macOS (Swift / AppKit) menu-bar prompt launcher. Hit ⌥Space in any text field, type a fragment, fuzzy-filter to the right template, hit ↵, and the fully-assembled prompt drops into the frontmost app with the cursor where it should be — ~700ms, focus never stolen. Solo side project, built first for the author's own daily use.

## Repository Structure

Stage 1 scaffold built (swiftc-based, no Xcode GUI). Gate 0 Tier B (5-app matrix) still pending.

```
CLAUDE.md            # this file
README.md            # pitch (user-facing) + dev status/run/docs-map
docs/                # full spec suite: PRD, FEATURES, DESIGN, TASKS
PasteProbe.swift     # spike: interactive probe of the paste loop (compiles with PasteCore.swift)
PasteProbeTests.swift # Tier A autonomous tests (compile w/ PasteCore.swift)
run.sh               # dev loop: compile x86_64 → bundle .app → install → relaunch → tail log
Promptly/            # the app sources, built with swiftc into /Applications/Promptly.app
  Info.plist         #   LSUIElement agent, com.promptly.app bundle id (TCC-stable)
  PasteCore.swift    #   paste logic extracted VERBATIM from the spike (one source of truth)
  Capture.swift      #   frontmost-app + screen capture (before any panel shows)
  HotkeyManager.swift#   Carbon ⌥Space global hotkey (consumes the event)
  PromptStore.swift  #   ~/Prompts loader, frontmatter parse, fuzzy filter, recents, fs-watch
  PasteService.swift #   main-thread paste orchestrator over PasteCore + read-back
  PanelController.swift # nonactivating NSPanel palette, 5 states, Mattmode Mono
  main.swift         #   AppDelegate, status item, AX-permission window, entry point
  Resources/SeedPrompts/ # bundled first-launch .md prompts
```

## Essential Commands

```bash
arch -x86_64 swift Promptly/PasteCore.swift PasteProbe.swift   # run the spike (Intel / x86_64)
./run.sh                                                       # build → install → relaunch → tail log
```

The pure paste logic now lives in `Promptly/PasteCore.swift` (extracted verbatim from the
spike); both the probe and the shipping `PasteService` compile against it — one source of truth.

Build everything for **Apple Intel (x86_64)** — see Boundaries.

## Architecture

The whole product is one risky loop. Prove it before building anything around it:

```
global hotkey (⌥Space) -> capture frontmost app -> nonactivating NSPanel + fuzzy filter
  -> paste service (AX direct write, clipboard fallback) -> back into the frontmost app
```

The staged roadmap (tokens, capture hotkey, frecency, adaptive cards) lives in the design doc; don't duplicate it here.

## Boundaries

### Always
- Native Swift / AppKit. No Electron/Tauri — they can't hit the never-steal-focus + paste-into-any-app bar.
- Build for Apple Intel / **x86_64** (`arch -x86_64` for the spike, `ARCHS=x86_64` for the app target). Universal/arm64 is an explicit future decision, not a default.
- Prove the paste loop before building UI or a store. Build AX direct write (Strategy B) before the clipboard fallback (Strategy A).

### Ask first
- Adding SQLite / GRDB / FTS5 — premature until the prompt library is large.
- Adding any dependency.
- Changing the global hotkey mechanism.

### Never
- Leave the clipboard mutated after a paste — always snapshot and restore.
- Commit signing secrets or certs.

## Things That Will Bite You

- Both paste paths need **Accessibility** permission — a silent-failure point. Check `AXIsProcessTrustedWithOptions` and surface a clear first-run state.
- **A rebuild can silently revoke Accessibility** (TCC keys on signature + bundle ID + path), which looks exactly like "the paste loop broke." Mitigate with stable `PRODUCT_BUNDLE_IDENTIFIER` + ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) + a fixed install path, all baked into `run.sh`. Escape hatch: `tccutil reset Accessibility <bundle-id>`. The spike grants Terminal; the app grants the bundle — the grant does **not** transfer.
- An AX `set` returning `.success` does **not** mean text landed (Electron/WebKit shims no-op silently). **Verify by read-back**, not by return code.
- Capture `NSWorkspace.frontmostApplication` **before** showing the panel, or you paste into your own panel.
- `NSEvent` global monitors can't consume the event; Carbon `RegisterEventHotKey` can. Pick deliberately (Carbon is the decided mechanism).

## Test & Self-Heal Loop

How to test the paste loop and fix bugs it surfaces. The cycle is the project's generic
[Self-Improvement Loop](#the-self-improvement-loop) made concrete for the paste service:

1. **Run the Tier A tests** (below). On red, read the full trace — `swiftc` errors, the failing
   assertion, the evidence dump.
2. **Fix the code, never the assertion.** A read-back miss or a non-clean clipboard is a *real
   bug* — the exact failure this whole project is structured to catch. Make the spike honest, not green.
3. **Re-run Tier A** until green.
4. **Then hand off Tier B** — lay out the cross-app matrix steps for the author; you cannot run them.
5. Update this section when you learn something durable (a new failure mode, a toolchain quirk).

Tests come in two tiers because the cross-app paste matrix fundamentally needs a human.

### Tier A — autonomous (an agent may run unattended)

Everything here runs headless with no foreign-app focus and no TCC approval beyond Terminal's.

> **Runnable today: only the typecheck gate.** The other three checks below need the
> `PasteCore.swift` extraction + a test file (see *Testability structure*, planned — not built
> yet). They activate in Stage 1; until then "keep Tier A green" means the typecheck gate passes.

- **Typecheck gate:** `arch -x86_64 swiftc -typecheck Promptly/*.swift` — must exit 0. *(Runs today.)*
- **Clipboard snapshot/restore round-trip** — assert the pasteboard is byte-identical after a
  Strategy A paste (the HARD RULE in DESIGN §2.4 and Boundaries → Never).
- **Capability-probe decision table** — feed synthetic `Evidence` to `choosePath` and assert every
  row of DESIGN §2.2, including the **clobber-ban** branch (value-settable + non-empty → A, §2.3).
- **In-process AX write + read-back** — create an `NSTextField` in this process, focus it, run the
  paste, and assert the marker landed by read-back (the proof model of DESIGN §2.1). Exercises the
  real native path end-to-end without a human.

### Tier B — human-in-the-loop (agent prepares, author runs)

- The **5-target cross-app matrix** in `docs/TASKS.md` (Gate 0): Terminal, Safari, Xcode, VSCode,
  Notes. It needs clicking into other apps and per-app Accessibility grants — an agent can neither
  focus foreign apps nor approve TCC. Your job: keep Tier A green and write out the matrix steps for
  the author to run.

### Testability structure (planned — not built yet)

When the harness gets written, keep **one** source of truth so `PasteService` and the tests can't
drift from the spike (DESIGN §5, "extract it verbatim"): extract the pure logic and strategies
(`choosePath`, `strategyB_selectedText`, `strategyB_valueSet`, `strategyA_clipboardPaste`,
`restoreClipboard`, `readBackConfirms`, `Evidence`) into `PasteCore.swift`; leave the interactive
`runProbe()` in `PasteProbe.swift`; compile tests via `swiftc PasteCore.swift <Tests>.swift`.

### Honesty rules (these gate "self-heal")

- **Never weaken or delete an assertion to go green.** Fix the cause.
- **Never leave the clipboard mutated; never value-set a non-empty field** (clobber ban). A test
  that "passes" by violating either is a regression, not a heal.
- If a fix touches paste behavior, re-run *all* of Tier A and flag that Tier B needs a re-run.
- Report which tier actually ran. **Never claim Gate 0 is green from Tier A alone** — the must-pass
  criterion is read-back confirmed in *real* apps, which only Tier B proves.

## Deeper Context

Specs live in `docs/`: **PRD** (product/feeling/non-goals), **FEATURES** (UX + ASCII mockups),
**DESIGN** (technical: paste service, hotkey, permissions, modules), **TASKS** (gated checklist).
The whole feature universe (committed/candidate/non-goal) is indexed in **`docs/FEATURE-CATALOG.md`**.

## How to Operate

**1. Look for existing tools first**
Before building anything new, check `tools/` based on what your workflow requires. Only create new scripts when nothing exists for that task.

**2. Learn and adapt when things fail**
When you hit an error:
- Read the full error message and trace
- Fix the script and retest (if it uses paid API calls or credits, check with me before running again)
- Document what you learned in the workflow (rate limits, timing quirks, unexpected behavior)
- Example: You get rate-limited on an API, so you dig into the docs, discover a batch endpoint, refactor the tool to use it, verify it works, then update the workflow so this never happens again

**3. Keep workflows current**
Workflows should evolve as you learn. When you find better methods, discover constraints, or encounter recurring issues, update the workflow. That said, don't create or overwrite workflows without asking unless I explicitly tell you to. These are your instructions and need to be preserved and refined, not tossed after one use.

## The Self-Improvement Loop

Every failure is a chance to make the system stronger:
1. Identify what broke
2. Fix the tool
3. Verify the fix works
4. Update the workflow with the new approach
5. Move on with a more robust system

This loop is how the framework improves over time.
