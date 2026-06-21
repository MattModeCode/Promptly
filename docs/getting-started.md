# Getting started with Promptly

By the end of this tutorial you'll have Promptly running, paste your first prompt into a real
app, and write one of your own. It takes about five minutes.

## What you'll need

- A Mac running macOS 12 (Monterey) or later
- The Promptly app — [download the latest release](https://github.com/MattModeCode/Promptly/releases/latest)

## Step 1: Install and open

1. Unzip the download and drag **Promptly.app** into your **Applications** folder.
2. **Right-click Promptly.app → Open → Open.** (Promptly is ad-hoc signed, so this one-time
   right-click is how macOS lets you run it. After that, double-click works normally.)

You'll see a small Promptly icon appear in your menu bar. There's no Dock icon and no window —
Promptly stays out of the way until you call it.

## Step 2: Grant Accessibility permission

Promptly types into other apps, which macOS guards behind Accessibility permission. On first
launch it opens **System Settings → Privacy & Security → Accessibility** for you — flip the
switch next to **Promptly** on.

> Without this, the palette still opens but the paste step can't run.

## Step 3: Summon the palette

Click into any text field — a note, an email, a code editor — and press **⌥Space**.

A palette drops down over your screen. You'll see one prompt already there: **Welcome to
Promptly**, pinned at the top with a **⌘1** badge. The app you were in keeps focus the whole
time; the palette is just floating on top.

## Step 4: Paste your first prompt

Press **⌘1** (or use the arrow keys and press **↵**).

The palette closes and the welcome text lands right where your cursor was. That's the entire
loop: summon, choose, paste — without ever leaving the app you're working in.

## Step 5: Write your own prompt

Open the menu-bar icon → **Open prompts folder…**. This is `~/Prompts`, where every prompt
lives as a Markdown file. Create a file called `hello.md`:

```markdown
---
name: My first prompt
hotkey: 2
---
Hi! This text was pasted by Promptly.
```

Save it. Promptly notices new files instantly — press **⌥Space** again and your prompt is there,
ready to fire with **⌘2**.

## What you built

You can now drop any saved prompt into any app with two keystrokes. From here:

- [How-to guides](how-to.md) — pin prompts, organize folders, use tokens, build a fill-in prompt
- [Reference](reference.md) — every frontmatter field, every token, every shortcut
- [Example prompts](example-prompts/) — a gallery of templates to copy into `~/Prompts`
