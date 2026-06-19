# FEATURES — UX & Interaction Spec

**Depth:** MVP specified deeply; stages 3–7 at tiered depth (intent + key decisions).
Sibling docs: [PRD.md](PRD.md) · [DESIGN.md](DESIGN.md) · [TASKS.md](TASKS.md)

The governing rule for every decision below: **make "what will ↵ do right now" legible at a
peripheral glance in under 100ms.** That legibility is what lets the hand stop looking — it is
the whole game.

---

## 1. Palette anatomy (MVP)

A single centered, nonactivating panel floating above the host app. It never steals focus.

- **Width:** ~560–640pt. **Corner radius:** ~12pt. **Background:** vibrancy/HUD material
  (`.hudWindow` or `.popover`), subtle 1px border + soft shadow so it reads as floating.
- **Position:** horizontally centered; vertically ~30–35% from the top (above true center,
  where the eye rests). **The input never moves; results grow downward only.** Spatial
  stability is what the hand learns.
- **Search field:** single line, ~17–18pt regular, generous padding (~12pt), no visible label,
  placeholder "Search prompts…".
- **Results list:** up to ~6 rows visible, each ~36–40pt tall.

### Row design — one prompt per row, title-forward

- **Title** in semibold (~15pt), primary.
- One-line **muted preview/snippet** (~12pt secondary) below or trailing.
- Fuzzy-matched characters in the title are **bold + accent-weighted** (weight + color, *not* a
  background swatch — swatches add noise).
- A trailing **⌥-number chip** slot is *designed-for but empty* in MVP (it fills in stage 7).
- No decorative icons in MVP.

### The selected row — unmistakable (this is the whole game)

The selected row (the one ↵ fires) gets a **full accent-tinted fill** (system accent ~15–20%
opacity) with its title at full strength; every other row sits quieter. The **first match is
auto-selected on every keystroke.** ↑/↓ move the selection and **clamp** at the ends (no
wrapping — wrapping disorients fast typists). The contrast between selected and unselected must
read in a peripheral glance.

---

## 2. The four MVP states

### State A — Default (just opened, nothing typed)

Shows the **top ~6 most-recently-used prompts immediately**, so ⌥Space-then-↵ does something useful.
Top row auto-selected. (MVP ranks by a simple last-used timestamp; usage-weighted *frecency* scoring
is Stage 6 — the empty state needs only recency, not the ranking engine. On a cold first launch with no
history, this falls back to seed order.)

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

On ↵: the selected row gives one fast confirmation cue (~80ms accent-fill pulse / micro-flash),
then the **whole panel** fades out in ~120ms with a tiny scale-down (0.98) — no slide, no bounce.
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
│            Prompt Palette                   │
│                                             │
│  To type prompts into other apps, Prompt    │
│  Palette needs Accessibility access.        │
│                                             │
│  It never reads your screen, and your       │
│  clipboard is always restored.              │
│                                             │
│            [ Open System Settings → ]       │
└────────────────────────────────────────────┘
```

- One sentence of *why*, one primary button that deep-links to the Accessibility pane
  (`x-apple.systempreferences:` URL), one tiny trust line. No carousel, no account, no tour.
- After granting, the app detects the change (re-check on next hotkey / poll `AXIsProcessTrusted`)
  and quietly becomes ready — ideally without a manual relaunch; if relaunch is unavoidable, that
  one line says so.
- The **menu-bar icon carries a subtle "not yet permitted" state** (dimmed/badged) as the
  persistent, non-nagging reminder.

---

## 5. Menu-bar dropdown (the only "settings")

No settings *window*. The menu-bar item's dropdown holds exactly the few real controls — keeping
"quiet and observant" for behavior while refusing to be a black box you can't recover from:

```
  Prompt Palette
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

### Stage 7 — Adaptive ⌥1–9 HUD row ("a keyboard, not a piano")
**Fixed 9 positions, always in the same place; only the *content* reorders** by app/time-of-day.
The number is the constant the hand learns; the label under it changes. **Positions freeze for
the duration of any single appearance — never animate a live reshuffle**; re-sort only between
opens. Shown as a thin persistent strip, numerals dominant.

```
  ⌥1 Standup   ⌥2 PR desc   ⌥3 Bug triage   ⌥4 Review   ⌥5 Cold intro   …   ⌥9 Cheatsheet
```

---

## 8. Visual-artifact policy

Mockups in this doc are **ASCII/Markdown only** — they live in git, stay diffable, cost nothing
to author, and double as the solo build checklist. We mock the **four MVP states + the commit
flow + the stage-4 transform**; later stages get intent prose, not full pixel specs.
