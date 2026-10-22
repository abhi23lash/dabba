# Dabba

A native iOS/iPadOS/macOS app for thinking on paper. You arrive cluttered, stuck or undecided, write freely, and leave with one clear line you wrote yourself. Working tagline: "Think on paper."

## What you're doing right now

The Xcode project was just created by hand in Xcode (Multiplatform → App, product name **Dabba**, SwiftUI, Storage: None, Swift Testing, git repo on). The first slice of code was drafted in another session but has **never been compiled**. Your job:

1. **Find the project.** It should be at `~/Developer/Dabba`, but it may have been saved somewhere else by mistake (Desktop, Documents, Downloads). If it isn't in `~/Developer`, quit Xcode, `mkdir -p ~/Developer`, move the whole `Dabba` folder there, and reopen `~/Developer/Dabba/Dabba.xcodeproj`. Confirm the move with the user first.
2. **Drop in the starter files** from `starter/Dabba/` (shipped next to this file) into the app's source folder `~/Developer/Dabba/Dabba/`, overwriting the template's `ContentView.swift` and `DabbaApp.swift`. The source folder is a synchronized folder, so new files and subfolders join the target automatically. Do not hand-edit `project.pbxproj`.
3. **Build and fix.** `xcodebuild -project Dabba.xcodeproj -scheme Dabba -destination 'platform=macOS' build`, then an iOS simulator destination. Expect a few compile errors; fix them without changing behaviour.
4. **Run it** on the Mac and an iPhone simulator, and have the user try a session: write a question, write, fill the landing, finish with ⌘↩, open the sessions list.
5. **Commit** once it builds and runs: "Writing page, sessions model and list".

Then stop and check in with the user before starting the next build step.

## The user

An experienced developer who is new to the Mac and Xcode. Don't dumb anything down. Explain Xcode-specific behaviour (signing, schemes, synchronized folders, simulators, previews) where it differs from other stacks, briefly. The user cares most about UI and UX: feel, motion and typography are the product.

## Principles (non-negotiable)

- **Build only what's needed, and build it great.** Few features, each obsessed over. Don't add features, settings or screens that aren't in the current step.
- **No AI in the app.** Nothing ever writes, completes, suggests or rewrites on the page. A later learning-mode feature may use an on-device decision model that judges but never writes; not now.
- **The page belongs to the writer.** Private and local. SwiftData on device; iCloud sync later. No analytics on writing content.
- **Guide, don't leave them alone.** Modes guide through the shape of the page and simple methods, not chatty prompts.
- **Think first, write second.** Messy writing first, a short revision pass after.
- **Not a notes app.** It's for thinking sessions, not storage.

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

Feel: warm, plain, unhurried, like good paper. Never pure white or pure black.

| Token | Light ("Paper") | Dark ("Night") | Use |
| --- | --- | --- | --- |
| paper | #F6F2EA | #171614 | Page and board ground |
| paperRaised | #FFFDF8 | #211F1C | Sheets above the page |
| ink | #22201C | #EDE8DF | Writing, primary text |
| inkMuted | #6B655B | #A39D92 | Labels, hints, dates |
| hairline | #DDD6C9 | #34312C | Rules and dividers |
| accent | #B5502F | #E8896A | Cursor, focus ring, strike-through only; one accent mark on screen at a time |

All text pairs pass WCAG AA in both themes (checked).

- **Type:** New York (`.system(design: .serif)`) for everything written; SF Pro for interface. Page 19pt/30 line, question 24pt italic, landing 22pt semibold, labels 13pt medium. Writing column about 65 characters (640pt).
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

1. **The page** ← current
2. **Sessions saved** ← included in the starter as a plain list
3. **One mode** (Stuck or Deciding)
4. **The fold:** the animation where a finished session folds into its block. Signature moment; spend real time on it.
5. **The board:** grid, drag and place, colors and marks, zoom levels
6. **Remaining modes, then learning mode**

The user should use each step daily for a few days before the next.

## Known gaps in the starter

- TextEditor placeholder inset is approximated and may misalign by a few points per platform.
- Spell-check squiggles are still on (the intent is none). SwiftUI has no direct API; may need a `UITextView`/`NSTextView` wrapper later.
- Fixed font sizes ignore Dynamic Type; revisit before release.
- Return in the question field moves focus to the writing area on submit; check behaviour on iOS with a vertical-axis `TextField`.

## Later, not now

On-device AI judging for learning mode via a decision model that only picks, never writes (prototype with TypeSafe's Jev, then a fine-tuned open-weight Laya on device). File uploads. Branching tangents and margins. Linking blocks, search. Boards as projects. iCloud sync.
