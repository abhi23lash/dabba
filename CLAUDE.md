# Dabba

A native iOS/iPadOS/macOS app for thinking on paper. You arrive cluttered, stuck or undecided, write freely, and leave with one clear line you wrote yourself. Working tagline: "Think on paper."

## The goal

Thinking is hard and a bit uncomfortable. Dabba makes it easier, so people keep writing and come to want to think better. That is the whole point and the moat; every feature is judged by whether it lowers that discomfort. The writing should feel enjoyable, never like homework.

## What you're doing right now

**Foundations first, then finishing Ideas mode on the Mac** (branch `ideas-mode`). Work one piece at a time; discuss and confirm scope with the user before building each.

Foundations (agreed 2026-10-23, in order):
1. Never lose text: save about a second after typing stops and when the app backgrounds or quits; check by force-quitting mid-sentence. Open in under a second with the cursor ready.
2. Open straight onto the current page instead of the board; the board stays one click away and is never required.
3. Keyboard first: every action has a shortcut and is in ⌘K (page/board ⌘B, side notes, leave mode, finish).
4. Local files: mirror each session as Markdown (see "Local files"), plus File ▸ Export (⌘⇧E) on the Mac.

How it works now: `/` opens modes (`/ideas`, `/open`), `@` opens models (`@inversion`), ⌘K lists both. A model opens inline as a tinted box where it was called; its heading and the writing under it live in `Session.text`, anchored by `Step`. Return twice on an empty line steps out of a box.

Scope agreed (2026-10-23):
1. First principles: a plain box with its explanation; earlier attempts get crossed out with strike instead of delete, no special behaviour (user call: special handling was over-engineered).
2. Inversion: one reason per line; any reason can flip into "For this to work…" under it (a control and a keystroke). Stacked in the box, not two columns.
3. Second-order: a chain of lines, each with a muted "and then…".
4. Moving through the mode (⌘↓/⌘↑, dots, hints) and the landing ("The idea is…", Finish) feel finished.
5. Ending that pushes action (user's problem: ideas go unworked because they're too big and there are too many). After "The idea is…", Ideas asks "The smallest version is…" (something to try in a weekend or less) and "The first step is…" with today / this week / someday. Candidates, not yet confirmed: an open question line ("What I still don't know is…") and Dabba resurfacing the first step at the chosen time with Did it / Not yet / Let it go.

Direction for these models (2026-10-23): make thinking easier, not add mechanics. Candidates under discussion: your own words carry forward (the First principles line quoted at the top of later models and by the landing), pause prompts (a few fixed questions per model that fade in only when you stop typing), and focus (earlier models fade back). Nothing generates text.

Out for now: iPhone parity (next round), closing the loop (board, blocks, what shapes mean, side notes after finishing), other modes, shapes for the other models, typewriter scrolling.

## The user

An experienced developer who is new to the Mac and Xcode. Don't dumb anything down. Explain Xcode-specific behaviour (signing, schemes, synchronized folders, simulators, previews) where it differs from other stacks, briefly. The user cares most about UI and UX: feel, motion and typography are the product.

## Principles (non-negotiable)

- **Build only what's needed, and build it great.** Few features, each obsessed over. Don't add features, settings or screens that aren't in the current step.
- **No AI in the app.** Nothing ever writes, completes, suggests or rewrites on the page. A later learning-mode feature may use an on-device decision model that judges but never writes; not now.
- **The page belongs to the writer.** Private and local: your writing lives on your device as files you can see and own. No analytics on writing content.
- **Guide, don't leave them alone.** Modes guide through the shape of the page and simple methods, not chatty prompts.
- **Writing is thinking.** You find out what you think by writing it. The page helps you keep writing; it never asks you to plan first.
- **Never preachy.** No guilt, streaks, scores or lectures. Dabba invites; it never scolds or blocks.
- **Not a notes app.** It's for thinking sessions, not storage.

## Local files (decided 2026-10-23)

Dabba keeps its SwiftData store, and also mirrors every session as a plain Markdown file in a folder the user can see (default `~/Documents/Dabba/`), updated as they write. One-way for now: edits made outside Dabba are not read back. The format is designed so files can later become the source of truth (an Obsidian-style vault, with iCloud Drive for sync):

```
---
dabba: 1
mode: ideas
created: 2026-10-23T10:00:00Z
finished: 2026-10-23T10:20:00Z
landing: a writing app that makes thinking easier
---
# Should I build Dabba?

Free writing, with ~~struck text~~ kept, and a side note mark.[^1]

## Inversion
Writing inside the model's box.
<!-- /model -->

[^1]: The side note's text.
```

## Stack

- SwiftUI multiplatform (iOS, iPadOS, macOS), one target. SwiftData for persistence.
- Every `@Model` property has a default or is optional, to stay CloudKit-compatible.
- Use `#if os(macOS)` / `#if os(iOS)` for platform differences; no Catalyst.
- No third-party dependencies unless clearly justified.

## Starter code (in `starter/Dabba/`)

| File | What it does |
| --- | --- |
| `DabbaApp.swift` | App entry, `.modelContainer(for: Session.self)`, Mac default window size |
| `ContentView.swift` | Opens straight onto the live draft (the one `Session` with `finishedAt == nil`); creates a new draft when none exists; corner button opens the sessions list |
| `Model/Session.swift` | `@Model Session`: `createdAt`, `finishedAt?`, `question`, `text`, `landing` |
| `Page/PageView.swift` | The writing page: question at top, `TextEditor` in the middle, landing pinned at the bottom; binds straight to the model so it autosaves; Finish (⌘↩) |
| `Sessions/SessionsView.swift` | Plain list of finished sessions plus a read-only session view; temporary until the board exists |
| `Theme/Paper.swift` | Design tokens: adaptive colors, fonts, column width |

Deliberate decision: **Finish is disabled until the landing line has text.** Every session has to land. The user may flip this.

## Design system

Feel: mechanical and methodical; the page is an instrument for thinking by writing. Plain white and neutral greys, no warmth, no brand color (user call, 2026-10-22: the earlier cream, terracotta and serif look read too close to Claude). The visual identity is still being worked out.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| paper | #FFFFFF | #141414 | Page and board ground |
| paperRaised | #FFFFFF | #1E1E1E | Sheets above the page |
| ink | #1A1A1A | #EDEDED | Writing, primary text |
| inkMuted | #6E6E6E | #9A9A9A | Labels, hints, dates |
| hairline | #E5E5E5 | #2E2E2E | Rules and dividers |
| accent | #1A1A1A | #EDEDED | Cursor, focus; plain ink for now, a functional signal color may come later |

All text pairs pass WCAG AA in both themes (checked).

- **Type:** SF Pro throughout (user call, 2026-10-22: easy on the eyes, not the focus; the serif read too close to Claude). Page 18pt with 8pt line spacing, question 22pt medium, landing 20pt semibold, labels 13pt medium. Writing column about 65 characters (640pt).
- **Depth:** flat. No shadows except the system drag lift.
- **Motion:** slow and physical, never bouncy. Respect Reduce Motion (cross-fade instead).
- **Icons:** SF Symbols, minimal; nothing on screen while typing.
- **Voice:** plain, calm, "you", sentence case, no exclamation marks, no emoji, no praise, no AI words ("smart", "insights").
- **Block colors are provisional.** Current placeholders: turmeric #E8BC5A, terracotta #D98A6A, leaf #9DBF8E, sky #9EC1D9, with marks in #22201C. The user is drawing inspiration from Sanzo Wada's *A Dictionary of Color Combinations*: dusty, printed-on-paper colors chosen as harmonious combinations. Don't finalize the block palette without the user.

## Product spec

**A session:** arrive (pick a mode or open a blank page) → think (free writing, no polish) → write (short revision pass on the part that matters) → land (one line in your own words) → keep (becomes a block on the board).

**Modes.** Guidance appears one step at a time and is always skippable.

| Mode | How the page guides | Landing stem |
| --- | --- | --- |
| Stuck | Name what's stuck, free write, cross out what isn't actionable | My next step is… |
| Cluttered | Timed brain dump, sort lines into "matters" and "doesn't" | The one thing is… |
| Deciding | Page splits into a column per option; make the case for each, then distill | I'm choosing… |
| Unclear | Free write, then rewrite it as if to a friend; boil down the truest line | What I actually feel is… |
| Open | Blank page | (none) |
| Learning | Read material, close it, explain from memory; source returns side by side; mark gaps, relearn, rewrite. No AI. Paste text or photo of notes | Explanation, round by round |

**Blocks and the board.** Each finished session becomes one block. Blocks live on a board the writer arranges like a Tetris board, at their own pace; arranging is a separate "after" mode.
- Block size comes from session length (whole grid units, 24pt cells, 4pt gaps). The writer never picks it.
- Color and marks are personal, inspired by Mumbai's dabbawala tiffin codes: a few colors combined with four marks (dot, bar, corner notch, ring), max two marks per block; the mode is the default mark. The app never assigns meaning to colors.
- Each block carries one line (its landing). From far away the board is color, shape and marks; zoom in and the line appears; tap to open the session.
- No game mechanics: no clearing lines, scores or falling pieces.

## Build order

1. **The page** ← done (strike instead of delete, side notes, commands, inline model boxes)
2. **Foundations:** never lose text, open onto the page, keyboard first, local Markdown files ← current
3. **One mode: Ideas,** Mac first
4. **Habit pairing (idea, not decided):** Dabba shows up at moments people would otherwise doomscroll, e.g. while a coding agent works. Claude Code hooks (or Shortcuts triggers) call links like `dabba://wait` / `dabba://done`; a small floating page appears and steps aside when the wait ends, without cutting off a sentence. The user is still thinking this through; don't build yet.
5. **iPhone parity** for the page and Ideas
6. **Use it daily for a few days,** fixing only what bothers the user
7. **Close the loop:** finished sessions on the board (waits on the user deciding what shapes mean). Includes "one current idea": a single idea you're working on, new ideas wait on a short shelf and cool off for a few days before they can become current, and you pick the next one from the shelf. Unworked ideas may fade over time and ask once: keep or let go.
8. **The fold:** the animation where a finished session folds into its block. Signature moment; spend real time on it.
9. **Remaining modes, then learning mode**

Finish each step before starting the next.

## Known gaps in the starter

- Strike instead of delete (2026-10-22): the writing area is a native `UITextView`/`NSTextView` (`Page/PageTextView.swift`). Deleting or typing over a selection strikes it through and fades it; single-character backspace deletes normally. Struck ranges are saved on `Session.struck`. A strike resets the text view's undo history (one undo step back to before the strike). Spell-check is off.
- Fixed font sizes ignore Dynamic Type; revisit before release.
- Return in the question field moves focus to the writing area on submit; check behaviour on iOS with a vertical-axis `TextField`.

## Later, not now

Custom modes (nice to have): make your own mode from models, ideally by saving a session you did as a mode rather than a builder screen. On-device AI judging for learning mode via a decision model that only picks, never writes (prototype with TypeSafe's Jev, then a fine-tuned open-weight Laya on device). File uploads. Branching tangents and margins. Linking blocks, search. Boards as projects. iCloud sync.
