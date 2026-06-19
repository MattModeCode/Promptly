# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A native macOS (Swift / AppKit) menu-bar prompt launcher. Hit ⌥Space in any text field, type a fragment, fuzzy-filter to the right template, hit ↵, and the fully-assembled prompt drops into the frontmost app with the cursor where it should be — ~700ms, focus never stolen. Solo side project, built first for the author's own daily use.

## Repository Structure

Pre-scaffold — only docs exist so far. Everything below the line is **planned, not yet created**.

```
CLAUDE.md          # this file
README.md          # short project blurb
─────────────────  # planned ↓
PasteProbe.swift   # spike: prove the paste loop before any app code (Step 1)
<AppTarget>/       # Xcode menu-bar app, built after the spike is green (Step 2)
```

## Essential Commands

```bash
arch -x86_64 swift PasteProbe.swift   # run the spike (Intel / x86_64)
# xcodebuild ARCHS=x86_64 ...         # added once the app target exists
```

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
- Capture `NSWorkspace.frontmostApplication` **before** showing the panel, or you paste into your own panel.
- `NSEvent` global monitors can't consume the event; Carbon `RegisterEventHotKey` can. Pick deliberately.

## Deeper Context

For the full vision, staged roadmap, and spike spec, see:
`~/.gstack/projects/MattModeCode-ai-prompt-shortcut-app/mc-main-design-20260618-225221.md`

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

## gstack

Use `/browse` from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools.

Available skills: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/design-shotgun`, `/design-html`, `/review`, `/ship`, `/land-and-deploy`, `/canary`, `/benchmark`, `/browse`, `/connect-chrome`, `/qa`, `/qa-only`, `/design-review`, `/setup-browser-cookies`, `/setup-deploy`, `/setup-gbrain`, `/retro`, `/investigate`, `/document-release`, `/document-generate`, `/codex`, `/cso`, `/autoplan`, `/plan-devex-review`, `/devex-review`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`, `/learn`
