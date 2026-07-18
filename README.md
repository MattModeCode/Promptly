<div align="center">

<img src="AppIcon.png" width="120" alt="Promptly icon">

# Promptly

**A native macOS menu-bar prompt launcher.**
Hit ⌥Space in any text field, fuzzy-find a template, press ↵ — and the fully assembled
prompt drops in right where your cursor was. Focus never leaves the app you're in.

![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-black)
![Built with](https://img.shields.io/badge/Swift-AppKit-orange)
![Universal](https://img.shields.io/badge/binary-Universal%20(arm64%20%2B%20x86__64)-blue)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

<div align="center">
  <img src="docs/screenshots/demo.gif" alt="Option-Space summons the palette over a document, then dismisses — the document never loses focus" width="640" />
  <br>
  <em><sub>⌥Space over a document you're already writing in. The window behind never loses focus.</sub></em>
</div>

---

You reach for the same prompts everywhere — code reviews, commit messages, standups, cold
emails. Promptly puts them one keystroke away, in *any* app, without ever stealing focus or
leaving your clipboard changed.

<table>
<tr>
<td width="50%"><img src="docs/screenshots/palette.png" alt="The palette floating over a TextEdit document, showing pinned cards and recent prompts"><br><em>Pinned cards on ⌘1–⌘9, then your most-used prompts.</em></td>
<td width="50%"><img src="docs/screenshots/library.png" alt="The three-pane Library window with folders, prompt list, and editor"><br><em>The Library — folders, pins, hotkeys, and the prompt body.</em></td>
</tr>
</table>

<div align="center">
  <img src="docs/screenshots/menubar.png" alt="The menu-bar dropdown showing Accessibility granted and the hotkey" width="340" />
  <br>
  <em><sub>It lives in the menu bar. No Dock icon, nothing in your way until you call it.</sub></em>
</div>

## Why you'll like it

- **It never takes focus.** A Carbon global hotkey opens a non-activating panel over whatever
  you're using — the app underneath stays active the whole time, caret and all.
- **Your prompts are just files.** Every prompt is a `.md` file in `~/Prompts`. Edit them in any
  editor and Promptly live-reloads; folders become categories. Nothing is locked in a database.
- **Ranked by how you actually work.** Fuzzy search over names, keywords and bodies, ordered by
  how often and how recently you fire each prompt.
- **Your clipboard comes back exactly as it was.** Promptly snapshots and restores it around
  every paste, and confirms the text really landed by reading it back — not by trusting a
  return code.

## Download

> [!NOTE]
> Promptly is **ad-hoc signed** (free, unnotarized), so macOS Gatekeeper needs a one-time
> nudge the first time you open it. The steps below handle it.

1. Download the latest **`Promptly-x.y.z.zip`** from the
   [**Releases page**](https://github.com/MattModeCode/Promptly/releases/latest).
2. Unzip it and drag **Promptly.app** into your **Applications** folder.
3. Open it once with a right-click: **right-click Promptly.app → Open → Open**.

<details>
<summary><strong>If Gatekeeper still refuses, or you'd rather use Terminal</strong></summary>

<br>

```bash
xattr -dr com.apple.quarantine /Applications/Promptly.app
```

Then double-click as normal.

</details>

> [!IMPORTANT]
> Promptly needs **Accessibility** permission to type into other apps. On first launch it opens
> System Settings for you — enable **Promptly** under **Privacy & Security → Accessibility**.
> Without it, the paste step can't run.

Requires **macOS 12 (Monterey) or later**. The download is a **Universal** binary and runs
natively on both Apple Silicon and Intel Macs.

## Usage

| Action | How |
|--------|-----|
| Open the palette | **⌥Space** in any text field |
| Filter prompts | start typing a fragment |
| Paste the selection | **↵** |
| Paste a pinned/numbered prompt | **⌘1**–**⌘9** |
| Preview the full body | **⇥** |
| Dismiss | **Esc** |
| Manage prompts | menu-bar icon → **Library…** |
| Open your prompts folder | menu-bar icon → **Open prompts folder…** |
| Rebind the hotkey | menu-bar icon → **Rebind Hotkey…** |

### Writing prompts

A prompt is a Markdown file in `~/Prompts` with optional YAML frontmatter:

```markdown
---
name: PR description           # display name (defaults to the filename)
keywords: [pull request, diff] # extra fuzzy-search terms
pinned: true                   # keep it at the top
hotkey: 1                      # paste instantly with ⌘1–⌘9
description: Summarize a diff   # shown in the Library
---
Summarize this diff as a PR description.

**What changed:** {{cursor}}
**Why:**
**Risk:**
```

The folder a prompt lives in becomes its category. Tokens (`{{clipboard}}`, `{{date}}`,
`{{cursor}}`, `{{ask:label}}`) expand when the prompt is pasted; unknown tokens stay literal so
typos are easy to spot. See [`docs/example-prompts/`](docs/example-prompts/) for ready-to-use
templates and the full format reference.

## How it works

The whole product is one tight loop, proven before anything was built around it:

```
⌥Space (Carbon global hotkey)
  → capture the frontmost app BEFORE any UI appears
  → show a non-activating NSPanel + fuzzy filter
  → paste service: AX direct write, with a clipboard-paste fallback
  → verify the text actually landed by reading it back
  → clipboard restored to exactly what it was
```

Promptly writes text through the Accessibility API when it can, and falls back to a
snapshot-restore clipboard paste when it can't — always confirming success by read-back rather
than trusting a return code.

<details>
<summary><strong>Build from source</strong></summary>

<br>

Promptly builds with `swiftc` directly — no Xcode project required.

```bash
# Dev loop: compile (native arm64) → bundle → install to /Applications → relaunch → tail logs
./run.sh

# Release build: Universal (arm64 + x86_64), ad-hoc signed, zipped to ./dist
./scripts/release.sh 0.1.0
```

> [!NOTE]
> A rebuild can silently revoke Accessibility permission (macOS keys it on signature + bundle
> id + path). If paste stops working after a rebuild, run
> `tccutil reset Accessibility com.promptly.app` and re-grant.

</details>

## Documentation

| Doc | What's inside |
|-----|----------------|
| [docs/getting-started.md](docs/getting-started.md) | Tutorial: from install to your first paste |
| [docs/how-to.md](docs/how-to.md) | Task recipes: pins, hotkeys, folders, tokens, fill-ins |
| [docs/reference.md](docs/reference.md) | Every frontmatter field, token, and shortcut |
| [docs/PRD.md](docs/PRD.md) | Product vision, the feeling, success gates, non-goals |
| [docs/FEATURES.md](docs/FEATURES.md) | UX and interaction spec, with mockups |
| [docs/DESIGN.md](docs/DESIGN.md) | Technical design: paste service, hotkey, permissions, modules |
| [docs/TASKS.md](docs/TASKS.md) | Gated build checklist |
| [docs/FEATURE-CATALOG.md](docs/FEATURE-CATALOG.md) | Index of every feature (committed, candidate, non-goal) |
| [docs/example-prompts/](docs/example-prompts/) | A gallery of starter prompts |

Working on the code with an AI assistant? [CLAUDE.md](CLAUDE.md) captures the architecture,
boundaries, and the gotchas most likely to bite.
