# FEATURES — UX & Interaction Spec

**Depth:** MVP specified deeply; stages 3–7 at tiered depth (intent + key decisions).
Sibling docs: [PRD.md](PRD.md) · [DESIGN.md](DESIGN.md) · [TASKS.md](TASKS.md) · [FEATURE-CATALOG.md](FEATURE-CATALOG.md)

The governing rule for every decision below: **make "what will ↵ do right now" legible at a
peripheral glance in under 100ms.** That legibility is what lets the hand stop looking — it is
the whole game.

---

## 0. Visual system — Mattmode Mono

> **Revamped 2026-07-18 → "Lightfall" (v0.2.0).** The visual system was rebuilt via a judged design
> review into **Lightfall** — the same dark / opaque / monochrome ethos at a higher finish: one
> unified surface ladder, a 3-step radius scale, a modular JetBrains Mono type scale (four weights),
> and a four-cue selected-row signal (fill plate + glowing left rail + top bevel + title luminance
> lift). Native Apple Silicon, still zero hue. **The live tokens now live in `Promptly/Palette.swift`;**
> the build-values table below is the historical Mattmode Mono baseline it grew from.

Chosen via `/design-shotgun` (2026-06-19) over a native-macOS direction and a hybrid. A
developer's command palette in the Cursor/Grok register: **opaque, monochrome, mono type, dark
only.** No translucency, no color. Approved reference render + comparison board live in-repo at
[`docs/design/`](design/) — [`variant-B.html`](design/variant-B.html) is the canonical mockup
(provenance: `/design-shotgun` output originally at
`~/.gstack/projects/MattModeCode-ai-prompt-shortcut-app/designs/main-palette-20260619/`). Build values:

| Role | Value |
|------|-------|
| Backdrop | `#0a0a0f` |
| Panel surface (opaque) | `#0f0f14` |
| Primary text | `#e2e8f0` · dimmed (unselected title) `#b8c0cc` |
| Secondary / snippet | `#94a3b8` |
| Footer / hint | `#64748b` |
| Selected-row fill | `rgba(226,232,240,0.10)` |
| Selected-row left bar | `rgba(226,232,240,0.55)`, 2px |
| Matched character | `#ffffff`, weight 600 |
| Font | **JetBrains Mono** (bundled; falls back to `.monospacedSystemFont`) |
| Corner radius | 6px · **no border** · shadow `0 24px 60px rgba(0,0,0,0.6)` |

---

## 1. Palette anatomy (MVP)

A single centered, nonactivating panel floating above the host app. It never steals focus.

- **Width:** ~560pt. **Corner radius:** 6px. **Background:** flat **opaque `#0f0f14`** (deliberately
  *not* vibrancy/HUD material), **no border**, soft drop shadow `0 24px 60px rgba(0,0,0,0.6)` so it
  reads as floating. Dark only.
- **Position:** horizontally centered; vertically ~30–35% from the top (above true center,
  where the eye rests). **The input never moves.** Spatial stability is what the hand learns.
  On **multi-monitor** setups the panel appears on the **display holding the captured frontmost
  app's key window** (derived at present-time from the capture snapshot — see DESIGN invariant 4;
  the screen is part of what `capture-before-present` snapshots), centered there, so it shows up
  where you are already working. Falls back to the main display if the captured app's screen
  can't be resolved.
- **Search field:** single line, ~14pt JetBrains Mono, generous padding, no visible label,
  primary text `#e2e8f0`, thin 1.5px caret, placeholder "Search prompts…".
- **Results list:** up to 6 rows visible (each ~38pt tall) in a **fixed-height viewport**. With
  >6 matches, ↓ scrolls the selection through the full list — the panel's height stays fixed and
  the inner content slides under the viewport, with a thin scroll hint at the trailing edge.
  ↑/↓ **clamp at the true ends of the full match list** (not the visible 6) and never wrap.
  Default state (recents) scrolls the same way when it exceeds 6.

### Row design — one prompt per row, title-forward

- **Title** in JetBrains Mono ~13pt, weight 500, `#e2e8f0` (dimmed to `#b8c0cc` when unselected).
- One-line **muted preview/snippet** (~12pt, `#94a3b8`) trailing, ellipsis-truncated.
- Fuzzy-matched characters in the title go **brighter pure-white + heavier weight** (`#ffffff`,
  weight 600) — weight + brightness, *not* a background swatch and *not* a colored accent
  (swatches add noise; this design has no color).
- **Truncation:** title has priority — the muted snippet truncates first (ellipsis), and only if
  the title alone would overflow ~560pt does the title itself ellipsis. A title min-width keeps it
  always readable; the snippet yields the space.
- **⌘-number chip:** MVP **collapses** the chip column — title + snippet use the full row width.
  Stage 7 reflows the row to introduce the trailing ⌘-number column when chips actually exist
  (a one-time geometry change, called out here so it's expected, not a surprise reshuffle).
- No decorative icons in MVP.

### The selected row — unmistakable (this is the whole game)

The selected row (the one ↵ fires) gets a **faint white/silver fill** (`rgba(226,232,240,0.10)`)
**plus a 2px silver left-edge bar** (`rgba(226,232,240,0.55)`), title at full `#e2e8f0` strength;
every other row sits quieter. No system-accent-blue tint — the marker is monochrome. The **first
match is auto-selected on every keystroke.** ↑/↓ move the selection and **clamp** at the ends (no
wrapping — wrapping disorients fast typists). The contrast between selected and unselected must
read in a peripheral glance — the **2px left-edge bar is the primary selection signal** (it carries
the glance); the fill is reinforcement. Validate both against
[`variant-B.html`](design/variant-B.html) at arm's length / with a squint: if the selection doesn't
read at a glance, strengthen the bar before the fill. Under **Increase Contrast** (§9), strengthen both.

---

## 2. The five MVP states

The keyboard footer (`↑/↓ move · ↵ paste · esc dismiss`) is **persistent across States
A0/A/B/C** — it is the wayfinding for an unsure hand, not a State-A-only flourish. Only State D
(the commit fade) drops it.

### State A0 — Empty library (no prompts on disk)

Distinct from State C: A0 means the library itself is empty (a fresh install before seeding, or the
`~/Prompts/` folder emptied), not that a query found nothing. One warm line that points at the fix
instead of a cold "No items found" — the menu-bar **"Open prompts folder…"** is the action.

```
┌──────────────────────────────────────────────────────────┐
│  Search prompts…                                          │
├──────────────────────────────────────────────────────────┤
│              No prompts yet.                               │
│       Drop a .md file in ~/Prompts to begin →             │
└──────────────────────────────────────────────────────────┘
        ↑/↓ move · ↵ paste · esc dismiss
```

### State A — Default (just opened, nothing typed)

Shows the **top ~6 most-recently-used prompts immediately**, so ⌥Space-then-↵ does something useful.
Top row auto-selected. (MVP ranks by a simple last-used timestamp; usage-weighted *frecency* scoring
is Stage 6 — the empty state needs only recency, not the ranking engine. On a cold first launch with no
history, this falls back to seed order.) When recents exceed 6, the list scrolls (see §1 — fixed
viewport, ↓ scrolls).

```
┌──────────────────────────────────────────────────────────┐
│  Search prompts…                                          │
├──────────────────────────────────────────────────────────┤
│ ▸ Bug report triage            file a structured bug …    │  ← selected (accent fill)
│   Cold outreach                short intro to a founder…  │
│   PR description               summarize the diff, risk…  │
│   Standup update               yesterday / today / block… │
│   Code review pass             review this diff for …     │
│   Token cheatsheet             demonstrates every token   │
└──────────────────────────────────────────────────────────┘
        ↑/↓ move · ↵ paste · esc dismiss
```

### State B — Active filtering

Debounced ~40ms; list reorders by match score; matched characters highlighted; top row
auto-selected. (Below: query `pr`.)

```
┌──────────────────────────────────────────────────────────┐
│  pr                                                       │
├──────────────────────────────────────────────────────────┤
│ ▸ PR description               summarize the diff, risk…  │  ← 'P','R' highlighted in title
│   Bug report triage            file a structured bug …    │  ← 'p','r' matched within words
│   Code review pass             review this diff for …     │
└──────────────────────────────────────────────────────────┘
```

### State C — No match

Field has text, zero results. A single quiet centered line — **never** an error color, never a shake.

```
┌──────────────────────────────────────────────────────────┐
│  asdfgh                                                   │
├──────────────────────────────────────────────────────────┤
│                  No match · ↵ to dismiss                  │
└──────────────────────────────────────────────────────────┘
```

### State D — Commit (↵ → paste → fade)

On ↵: the selected row gives one fast confirmation cue (~80ms brightness pulse — lift the fill
toward `rgba(226,232,240,0.12)`), then the **whole panel** fades out in ~120ms with a tiny
scale-down (0.98) — no slide, no bounce.
The paste fires *during/under* the fade, so the assembled text appears in the host app as the
palette clears, making the two feel causally linked ("I pressed, it went there").

```
   selected row pulses (~80ms)        panel fades + scales to 0.98 (~120ms)
   ┌─────────────────────────┐               ┌───────────┐
   │ ▸ PR description  ✦ ✦ ✦ │    ───────▶   │  (fading) │   ───▶   (gone)
   └─────────────────────────┘               └───────────┘
                                   text now present in the host app's field, cursor placed
```

**Open vs close asymmetry:** opening is faster and flatter (~80–100ms fade-in, no scale) —
appearing must feel *instant*; disappearing can have one frame of grace. **Esc** dismisses with
the same fade but no pulse and no paste.

**Reduce Motion:** under `accessibilityDisplayShouldReduceMotion` the ~80ms pulse + ~120ms fade +
0.98 scale collapse to an instant dismiss (or a short opacity-only crossfade) — no scale, no pulse.
The paste still fires; only the choreography is dropped. The ~700ms feel is about latency, not
animation, so dropping the motion never delays the paste.

---

## 3. Paste feedback — silent success, loud failure

- **Success:** the panel just vanishes. The pasted text is the confirmation. No sound, no badge.
- **Failure** (neither paste path lands within a short window — AX revoked, an app that rejects
  AX writes, ⌘V not honored): the panel **does NOT fade**. It stays and shows one quiet line —

  ```
  ┌──────────────────────────────────────────────────────────┐
  │  Couldn't paste — copied to clipboard instead             │
  └──────────────────────────────────────────────────────────┘
  ```

  …and leaves the assembled text on the clipboard as the safety net (restored on next action).
  Silence when it works; one honest line when it doesn't.

---

## 4. First-run Accessibility moment (lazy)

The app is dead without Accessibility permission, but we do **not** prompt on launch. The **first
⌥Space that finds no permission** opens one small centered window instead of failing silently —
so the very first reflex is always *meaningful* (it either pastes, or explains why it can't):

```
┌────────────────────────────────────────────┐
│                  Promptly                   │
│                                             │
│  To type prompts into other apps, Promptly  │
│  needs Accessibility access.                │
│                                             │
│  It never reads your screen, and your       │
│  clipboard is always restored.              │
│                                             │
│            [ Open System Settings → ]       │
└────────────────────────────────────────────┘
```

- One sentence of *why*, one **ghost button** ("Open System Settings →" — transparent bg,
  `1px rgba(226,232,240,0.25)` border, `#e2e8f0` text, hover fill `rgba(226,232,240,0.06)`) that
  deep-links to the Accessibility pane (`x-apple.systempreferences:` URL), one tiny trust line.
  Same `#0f0f14` / JetBrains Mono surface as the palette. No carousel, no account, no tour.
- After granting, the app detects the change (re-check on next hotkey / poll `AXIsProcessTrusted`)
  and quietly becomes ready — ideally without a manual relaunch; if relaunch is unavoidable, that
  one line says so.
- The **menu-bar icon carries a subtle "not yet permitted" state** (dimmed/badged) as the
  persistent, non-nagging reminder.
- **Focus:** this window is the **one** surface allowed to activate / take focus — at first grant
  the user isn't mid-task, so the never-steal-focus discipline is suspended here and only here.
  While ungranted, each permission-less ⌥Space **re-opens this same window** (a single instance,
  never stacks); the dimmed menu-bar icon carries the reminder between attempts.

---

## 5. Menu-bar dropdown (the only "settings")

No settings *window*. The menu-bar item's dropdown holds exactly the few real controls — keeping
"quiet and observant" for behavior while refusing to be a black box you can't recover from:

```
  Promptly
  ─────────────────────────────
  Accessibility: ✓ Granted          (or: ⚠ Not granted — Fix…)
  Hotkey: ⌥Space            Rebind…
  Open prompts folder…
  ─────────────────────────────
  Quit
```

Principle: **the system's judgment is not configurable; the system's plumbing is inspectable.**

---

## 6. Keyboard model (MVP)

| Key | Action |
|-----|--------|
| ⌥Space | Toggle the palette (captured globally; consumed so it never leaks to the host app). |
| type | Filter (40ms debounce); first match auto-selects. |
| ↑ / ↓ | Move selection (clamp at ends). |
| ↵ | Paste the selected prompt into the captured frontmost app, then fade. |
| esc | Dismiss without pasting (same fade, no pulse). |

---

## 7. Later stages — tiered depth (intent + key decisions)

### Stage 3 — Static tokens `{{clipboard}}` `{{date}}` `{{cursor}}`
Substituted at paste time. **Unknown tokens stay literal** (a typo'd `{{clipboard}}` pastes
verbatim so the mistake is visible — there's no help panel). `{{cursor}}` marks where the caret
lands after paste; it is **precise only on the AX path** and degrades to caret-at-end on the
clipboard fallback (see DESIGN → paste service). Discoverability: a seed **"token cheatsheet"**
prompt + a header comment in the prompt files.

### Stage 4 — `{{ask:label}}` inline expansion (highest-value, highest-risk later UX)
On ↵, instead of paste-and-close, the palette **transforms in place** into a minimal fill-in
flow — the search field becomes the answer field, the label is the placeholder, ↵ advances to
the next `{{ask}}` or fires the paste on the last. **Critical rule: the panel must not move or
resize jarringly** — same surface changing role, preserving spatial trust. Tab and ↵ both
advance; esc cancels the *whole* expansion. Show progress quietly (e.g. "1 of 3" / a row of dots).

```
   prompt: "Hi {{ask:name}}, I loved your work on {{ask:project}}."
   ┌──────────────────────────────────────────────┐
   │  name ›  ▏                          (1 of 2)  │   ↵ → advances to "project", then pastes
   └──────────────────────────────────────────────┘
```

### Stage 5 — Inverse capture "save as prompt" sheet
Select text anywhere → capture hotkey → a small nonactivating sheet, **pre-filled with the
captured text as the body**, cursor in an empty **title** field (the one thing you must supply).
Hint that dynamic bits could become `{{tokens}}` (later). ↵ saves a new markdown file; esc
discards. Same focus-respecting discipline as the palette. *Acceptance criteria only at this stage.*

### Stage 7 — Adaptive ⌘1–9 HUD row ("a keyboard, not a piano")
**Fixed 9 positions, always in the same place; only the *content* reorders** by app/time-of-day.
The number is the constant the hand learns; the label under it changes. **Positions freeze for
the duration of any single appearance — never animate a live reshuffle**; re-sort only between
opens. Shown as a thin persistent strip, numerals dominant.

```
  ⌘1 Standup   ⌘2 PR desc   ⌘3 Bug triage   ⌘4 Review   ⌘5 Cold intro   …   ⌘9 Cheatsheet
```

### Stage 8 — Manual pinning ("a keyboard you can also relabel")
Stage 7's ⌘1–9 are auto-sorted by frecency. Stage 8 lets the user **pin** up to 9 prompts to a
chosen ⌘-number (frontmatter `pinned: true` + `hotkey: 3`; `pin: 3` is legacy, read-migrated only). **Hybrid rule:** a pin claims its exact number first; any
slot left unpinned auto-fills from the existing frecency assignment. ⌘1–9 stay **palette-only** —
no new global hotkeys, no height/resize math touched (a draw-only chip change over the frozen HUD map).

A **pinned chip reads differently from a frecency chip** — "permanent promise" vs. "today's guess".
The pinned chip is drawn as a filled/bracketed pill in primary text; the frecency chip is bare,
dim footer text:

```
   ┌──────────────────────────────────────────────────────────┐
   │  Search prompts…                                          │
   ├──────────────────────────────────────────────────────────┤
   │ ▸ Bug report triage         file a structured bug …  ▐⌘3▌ │  ← PINNED: filled pill, primary text
   │   Cold outreach             short intro to a founder…  ⌘5 │  ← frecency: bare, dim footer
   │   PR description            summarize the diff, risk…  ⌘1 │  ← frecency: bare, dim footer
   └──────────────────────────────────────────────────────────┘
           ↑/↓ move · ↵ paste · esc dismiss
```

**The pin shows even while filtering.** A frecency chip only appears in the resting empty-query
state (it's a guess about *now*); a pinned chip shows in **both** the empty state and mid-filter,
because the pin is a persistent promise the hand can trust regardless of what's typed:

```
   query "co" — frecency chips suppressed, but the pinned chip persists
   ┌──────────────────────────────────────────────────────────┐
   │  co                                                       │
   ├──────────────────────────────────────────────────────────┤
   │ ▸ Cold outreach             short intro to a founder…     │  ← frecency chip gone while filtering
   │   Code review pass          review this diff for …   ▐⌘3▌ │  ← PINNED: chip still shown
   └──────────────────────────────────────────────────────────┘
```

**Conflict (two prompts pin the same number):** deterministic winner keeps the slot, the loser is
treated as unpinned for this appearance — **neither file is silently rewritten** (the surfaced
warning belongs to the Library window, Stage 10). Out-of-range pins are ignored.

### Stage 9 — Three-pane Library window
A growing library outgrows a one-line palette. Stage 9 adds a **management window** — sidebar |
list | detail — opened from the menu bar. Its detail pane **replaces** the modal prompt editor.

**Off-paste-path invariant:** unlike the palette, this is a **normal, focus-taking app window**.
That is safe *precisely because it never pastes into another app* — it only browses, searches,
creates, edits, organizes, and pins. It never calls capture / present / the paste service, so the
"never steal focus" discipline (which exists only to protect a paste into the frontmost app) simply
does not apply here. The fast ⌥Space palette and the ~700ms loop are untouched.

```
   ┌─────────────────┬──────────────────────────┬─────────────────────────────────────┐
   │ ▪ all        7  │  ⌕ Filter…               │  title                              │
   │ ★ pinned     3  │ ┌──────────────────────┐ │  ┌───────────────────────────────┐  │
   │ ◷ recent        │ │ Bug report template  │ │  │ Bug report template           │  │
   │                 │ │ Structured repro for │ │  └───────────────────────────────┘  │
   │ folders         │ │ filing issues        │ │  folder            pin     hotkey   │
   │ ▸ Engineering 3 │ ├──────────────────────┤ │  ┌────────────┐  ( ●) ┌──────────┐  │
   │ ▸ Comms       2 │ │ Code review checklist│ │  │ Engineering▾│       │ ⌘1       │  │
   │ ▸ Writing     2 │ │ What to check before │ │  description                        │
   │ + new folder    │ │ approving a PR       │ │  ┌───────────────────────────────┐  │
   │                 │ ├──────────────────────┤ │  │ Structured repro for filing … │  │
   │                 │ │ Explain this code    │ │  └───────────────────────────────┘  │
   │                 │ │ Walk through a       │ │  body  supports {{clipboard}},      │
   │                 │ │ snippet step by step │ │        {{date}}, {{cursor}}         │
   │                 │ └──────────────────────┘ │  ┌───────────────────────────────┐  │
   │                 │                          │  │ ## Summary                    │  │
   │                 │                          │  │ ## Steps to reproduce         │  │
   │                 │                          │  │ ## Expected                   │  │
   │                 │                          │  └───────────────────────────────┘  │
   │                 │                          │  used 42× · last used 2h ago        │
   │                 │                          │                        [ delete ]   │
   └─────────────────┴──────────────────────────┴─────────────────────────────────────┘
```

- **Left — sidebar:** `all` / `pinned` / `recent` (with counts), a `folders` header with one row per
  real subdirectory of `~/Prompts/` (each counted), and `+ new folder`. Folders are real dirs, not tags.
- **Middle — list:** a `Filter…` field over the selected scope; two-line cards (title + description).
- **Right — detail (the editor):** title; a row of folder dropdown + `pin` toggle + editable hotkey
  field; description; body textarea (tokens supported); a `used N× · last used …` line; red `delete`.

**Pin/hotkey conflicts resolve by a user-initiated steal.** Turning the pin toggle on with a number
already held by another prompt clears that prompt's `pinned:`/`hotkey:` (rewriting its file), claims the slot for
the one being edited, and shows an inline warning: `⌘3 was on 'X' — moved here`. This is deliberately
destructive — distinct from Stage 8's *silent, non-destructive* load-time conflict handling (which
never rewrites a file). At load nothing is touched; here the user explicitly asked to take the slot,
so the editor rewrites it and says so.

Same Mattmode Mono surface as the palette — see §8.

### Stage 10 — Library polish
No new mockup (same window). Adds: **drag-to-move** a prompt between sidebar folders; **folder
rename**; an **inline pin-conflict banner** that surfaces Stage 8's *silent* load-time conflict (two
files on disk declaring the same `hotkey:` — the deterministic loser is unpinned for assignment but its
file is never touched) — this is render-only, the opposite of Stage 9's steal: nothing is rewritten,
the banner just tells the loser's editor "⌘3 is already on 'X'" so a human can resolve it; and
**relative-time** usage display (`"2h ago"`, `"yesterday"`, `"3d ago"`) replacing a raw timestamp.

---

## 8. Visual-artifact policy

Mockups in this doc are **ASCII/Markdown only** — they live in git, stay diffable, cost nothing
to author, and double as the solo build checklist. We mock the **four MVP states + the commit
flow + the stage-4 transform**; later stages get intent prose, not full pixel specs.

The one pixel-accurate render is the approved `/design-shotgun` output (§0):
[`docs/design/variant-B.html`](design/variant-B.html), committed in-repo (provenance:
`~/.gstack/projects/MattModeCode-ai-prompt-shortcut-app/designs/main-palette-20260619/`). Treat it
as the visual source of truth for the palette; the ASCII states above show layout/behavior, the
render shows the look.

The Library window (§7, Stage 9) is a **second surface** but not a second visual language: it reuses
the same Mattmode Mono `Palette` token set (extracted into a shared file so panel and window can't
drift) — opaque, monochrome, JetBrains Mono, dark only. Its ASCII mockup above is the only spec it gets.

---

## 9. Accessibility of the palette itself

The app is built on the Accessibility *API*; the palette must also *be* accessible. Three system
settings to honor (all are read-once-at-present, cheap):

- **Reduce Motion** (`accessibilityDisplayShouldReduceMotion`) — the commit choreography collapses
  to instant / opacity-only; the paste is never delayed (§2 State D).
- **Increase Contrast** (`accessibilityDisplayShouldIncreaseContrast`) — strengthen the selection
  bar and fill so the "whole game" peripheral signal survives a higher-contrast environment; the
  footer/snippet dim values lift toward their primary-text neighbors.
- **VoiceOver** — each row exposes an accessibility label like "`<name>`, `<snippet>`, prompt" and
  the selected row is announced on ↑/↓; the search field is labeled "Search prompts." The palette
  is already keyboard-first, so every affordance is reachable by the documented keys (§6) — there is
  nothing mouse-only to make accessible.

This section governs the colors/motion in §0–§2; where they conflict, the accessibility setting wins.
