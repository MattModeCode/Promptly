# How-to guides

Task-oriented recipes. They assume you've finished [Getting started](getting-started.md). For
exhaustive detail on fields and tokens, see the [Reference](reference.md).

## How to create a prompt

A prompt is a Markdown file in `~/Prompts`. Either:

- **From the app:** menu-bar icon → **Library…** → **+**, then fill in the title and body, or
- **By hand:** open the menu-bar icon → **Open prompts folder…** and add a `.md` file.

The filename can be anything; the display name comes from the `name:` frontmatter field (or the
filename if you omit it).

## How to pin a prompt

Pinned prompts always sit at the top of the palette and the Library. Add `pinned: true` to the
frontmatter, or toggle the pin in the Library detail pane:

```markdown
---
name: Code review pass
pinned: true
---
```

## How to assign a ⌘1–⌘9 shortcut

Give a prompt a `hotkey:` between 1 and 9 to fire it instantly from the palette:

```markdown
---
name: Standup update
hotkey: 3
---
```

Now **⌥Space** then **⌘3** pastes it. Pinning and hotkeys are independent — a prompt can have
either, both, or neither. If two prompts claim the same number, the one whose filename sorts
first keeps it and the Library flags the conflict (nothing is overwritten).

## How to organize prompts into folders

Put a prompt in a subfolder of `~/Prompts` and that folder becomes its category:

```
~/Prompts/
  Engineering/
    code-review-pass.md
  Writing/
    cold-outreach.md
```

The folder is read from the directory — you never write it in frontmatter. Move a file between
folders and Promptly re-categorizes it on the next reload.

## How to use tokens

Tokens in a prompt body expand the moment it's pasted:

```markdown
---
name: Daily log entry
---
## {{date}}

Clipboard: {{clipboard}}
Notes: {{cursor}}
```

- `{{date}}` becomes today's date (e.g. `2026-06-21`)
- `{{clipboard}}` becomes whatever text is on your clipboard
- `{{cursor}}` is where the caret lands after the paste, so you can start typing immediately

Unknown tokens are left exactly as written, so a typo like `{{dat}}` shows up in the output
instead of vanishing.

## How to build a fill-in prompt

Use `{{ask:label}}` to have Promptly prompt you for a value before pasting:

```markdown
---
name: Thank-you note
---
Hi {{ask:recipient}},

Thanks for {{ask:what they did}}. It meant a lot.
```

When you paste this, the palette turns into a small fill-in field and asks for each label in
order (**↵** or **Tab** to move on, **Esc** to cancel). Your answers drop into place, then the
finished text is pasted.

## How to change the global hotkey

Don't want ⌥Space? Menu-bar icon → **Rebind…** and press your preferred combination.

## How to build from source

You need the Xcode command-line tools (`xcode-select --install`); no Xcode project required.

```bash
# Dev loop: compile, bundle, install to /Applications, relaunch, tail logs
./run.sh

# Release build: Universal (arm64 + x86_64), ad-hoc signed, zipped into ./dist
./scripts/release.sh 0.1.0
```

> If paste stops working right after a rebuild, macOS has likely dropped the Accessibility
> grant (it keys on the signature, bundle id, and path). Reset and re-grant:
> `tccutil reset Accessibility com.promptly.app`.
