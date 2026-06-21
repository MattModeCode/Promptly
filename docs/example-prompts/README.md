# Example prompts

A small gallery of ready-to-use prompt templates. Promptly ships with just one starter
prompt ([Welcome to Promptly](../../Promptly/Resources/SeedPrompts/welcome-to-promptly.md)),
so this folder is here if you want more to begin with.

To use one, copy the `.md` file into your `~/Prompts` folder (open it from the Promptly
menu-bar icon → "Open prompts folder…"). Promptly picks up new files instantly.

## Prompt file format

Each prompt is a Markdown file with optional YAML frontmatter:

```markdown
---
name: PR description          # display name (defaults to the filename)
keywords: [pull request, diff] # extra fuzzy-search terms
pinned: true                  # keep it at the top of the list
hotkey: 1                     # paste instantly with ⌘1–⌘9
description: One-line summary  # shown in the Library
---
The body is the text that gets pasted. It can contain tokens like {{date}},
{{clipboard}}, {{cursor}}, and {{ask:your question}}, which expand on paste.
```

The folder a prompt lives in (under `~/Prompts`) becomes its category — frontmatter never
needs a folder key.

## In this folder

| File | What it's for |
|------|----------------|
| `pr-description.md` | Summarize a diff as a PR description |
| `code-review-pass.md` | Structured code-review checklist |
| `commit-message.md` | Conventional commit message from a diff |
| `bug-report-triage.md` | File a structured bug report |
| `refactor-plan.md` | Plan a refactor safely |
| `standup-update.md` | Daily standup template |
| `slack-update.md` | Short async team update |
| `cold-outreach.md` | Direct, no-fluff outreach message |
| `explain-to-rubber-duck.md` | Talk through a problem to find the flaw |
| `token-cheatsheet.md` | Reference for Promptly's token grammar |
