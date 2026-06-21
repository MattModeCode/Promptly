# Reference

Complete, exact description of the prompt file format, tokens, and shortcuts. For step-by-step
recipes see the [How-to guides](how-to.md); for *why* the paste loop is built the way it is, see
[DESIGN.md](DESIGN.md).

## Prompt files

- **Location:** `~/Prompts` (created on first launch).
- **Format:** a Markdown file (`.md`) with optional YAML frontmatter between `---` fences,
  followed by the prompt body.
- **Discovery:** the folder is scanned recursively and watched live — adding, editing, or
  removing a file takes effect without a restart.
- **Category:** a prompt's folder is its parent directory under `~/Prompts` (a file at the root
  has no category). The folder is never written in frontmatter.

```markdown
---
name: PR description
keywords: [pull request, diff, summary]
pinned: true
hotkey: 1
description: Summarize a diff as a PR description
---
The body that gets pasted. It may contain tokens (see below).
```

### Frontmatter fields

All fields are optional. Unknown keys are ignored.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `name` | string | the filename | Display title in the palette and Library. |
| `keywords` | list of strings | empty | Extra terms for fuzzy search, e.g. `[pull request, diff]`. |
| `pinned` | boolean | `false` | Keeps the prompt at the top. Independent of `hotkey`. |
| `hotkey` | integer 1–9 | none | Fires the prompt with ⌘1–⌘9. Never auto-assigned. |
| `description` | string | none | One-line summary shown in the Library list. |

> **Legacy `pin: N`.** Older files that combined pin + number in a single `pin:` key are read
> transparently and treated as `pinned: true` + `hotkey: N`.

### Hotkey conflicts

If two files declare the same `hotkey`, resolution is deterministic and non-destructive: the
file whose name sorts first keeps the slot, the other is treated as having no hotkey for
assignment, and the Library window surfaces the conflict. Neither file is modified.

## Tokens

Tokens expand when a prompt is pasted. Whitespace inside the braces is ignored (`{{ date }}`
works). Any token that isn't recognized is left **literal**, so typos stay visible.

| Token | Expands to | Notes |
|-------|------------|-------|
| `{{clipboard}}` | The current clipboard text | Empty clipboard expands to nothing (logged). |
| `{{date}}` | Today's date as `yyyy-MM-dd` | ISO-8601, in your local time zone, e.g. `2026-06-21`. |
| `{{cursor}}` | Nothing — marks the caret position | Only the first `{{cursor}}` counts; any others are removed. Exact on the AX paste path; falls back to end-of-text on the clipboard path. |
| `{{ask:label}}` | Your typed answer | Interactive fill-in, resolved before paste (see below). |

### `{{ask:label}}` fill-in

When a prompt contains one or more `{{ask:label}}` tokens, pasting it first walks you through
each label in document order:

- The palette becomes a fill-in field showing the current label and a quiet "k of N" position.
- **↵** or **Tab** records the answer and advances.
- **Esc** cancels the whole expansion (no partial paste).
- Empty labels (`{{ask:}}`) are ignored.

Answers fill their tokens in order, then any static tokens (`{{date}}`, etc.) expand, and the
finished text is pasted.

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| **⌥Space** | Open the palette over the frontmost app (rebindable via menu-bar icon → Rebind…). |
| *type* | Fuzzy-filter prompts by name and keywords. |
| **↵** | Paste the highlighted prompt. |
| **⌘1**–**⌘9** | Paste the prompt assigned to that number. |
| **↑ / ↓** | Move the selection. |
| **Esc** | Dismiss the palette (or cancel a fill-in). |

## Menu-bar actions

Click the Promptly menu-bar icon for:

- **Library…** — the three-pane window to add, edit, pin, and organize prompts.
- **New Prompt…** — create a prompt.
- **Open prompts folder…** — reveal `~/Prompts` in Finder.
- **Rebind…** — change the global hotkey.
- **Quit Promptly** (**⌘Q**).

## Ranking

The palette orders prompts by **frecency** — a blend of how often and how recently you use each
one — so your most-used prompts surface first. Pinned prompts are shown in their own section at
the top regardless of frecency.

## See also

- [Getting started](getting-started.md) — install to first paste
- [How-to guides](how-to.md) — task recipes
- [DESIGN.md](DESIGN.md) — the paste loop, strategies, and permissions model
- [example-prompts/](example-prompts/) — ready-to-use templates
