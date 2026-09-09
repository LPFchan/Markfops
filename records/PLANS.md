# Markfops Plans

This document contains accepted future direction only.
Do not put raw brainstorms or untriaged intake here.

## Planning Rules

- Only accepted future direction belongs here.
- Plans should be specific enough to guide implementation later.
- Architecture rationale should link to `DEC-*` records where possible.
- When a plan becomes current truth, reflect it into `SPEC.md` or `STATUS.md` and update this file.

## Approved Directions

### Native Reader View

- Outcome: the reader view is a second styling of the editor's own native text, with syntax hidden, proportional prose, styled headings, and inline-code capsules. The web preview is gone from the reading path; HTML serves PDF export only.
- Why this is accepted: one text engine removes the two-engine coordination problems that stalled the April research; see `DEC-20260909-001` and `DEC-20260909-002`.
- Expected value: scroll synchronization becomes trivial, cross-view motion becomes possible, and the native WYSIWYG engine gets its rendering layer without a duplicate web pipeline.
- Preconditions: none; slice 1 (`MarkdownSourceMap`) and slice 2 (reader mode) have landed.
- Earliest likely start: in progress
- Related ids: `DEC-20260909-001`, `DEC-20260909-002`, `RSH-20260909-001`

### Measured-Position Text Morphing

- Outcome: switching between editor and reader stylings animates each visible glyph from its position in one styling to its position in the other, driven by Core Animation, following the approach validated in `RSH-20260909-001`.
- Why this is accepted: the spike showed the motion is cheap and looks right, and the landed slice confirmed pairing through source spans works on the real views.
- Expected value: the continuity the research program set out to achieve, without a font that interpolates between monospace and proportional forms.
- Preconditions: none; landed as slice 3.
- Earliest likely start: landed
- Related ids: `DEC-20260909-001`, `RSH-20260909-001`, `RSH-20260402-012`

### Source-Mapped Formatted Editing

- Outcome: formatted mode is editable. Edits route through the reader's source map to the exact Markdown range, syntax reveals around the text cursor Typora-style, the cursor carries across mode switches, and revealed syntax morphs like other characters.
- Why this is accepted: the operator's original March goal, made safe by the per-character source map the native reader now has; see `DEC-20260910-001`.
- Expected value: writing in the formatted view without the innerText corruption that forced the April read-only decision; shared undo with monospace mode.
- Preconditions: none; the native reader and morph are on main.
- Earliest likely start: in progress
- Related ids: `DEC-20260910-001`, `DEC-20260909-001`, `RSH-20260909-001`

### Deferred But Accepted: Block-Aware Native Editing

- Outcome: Markfops introduces more explicit block-aware editing only after the native reader and morphing foundations prove out.
- Why this is accepted: the research program identified block-aware editing as valuable, but too risky as the first migration step.
- Expected value: richer structural editing without abandoning Markdown-first persistence.
- Preconditions: native reader styling and morphing are stable.
- Earliest likely start: version 2 of the engine program
- Related ids: `DEC-20260409-003`, `RSH-20260402-006`, `RSH-20260402-009`

## Sequencing

Each slice must end with something visible in the app and its own tests.

### Landed

- Slice 1: derive a per-character kind map from the existing cmark-gfm parse
  - Why now: cmark already exposes start and end positions for every node, including inline nodes, so this is the cheapest possible source of "which characters are syntax and which construct owns them"
  - Done when: the map feeds heading extraction (replacing the separate line scanner) and syntax highlighting, with tests covering headings, inline code, emphasis, links, and multi-byte text
  - Related ids: `DEC-20260909-001`, `IBX-20260409-001`, `IBX-20260409-002`
- Slice 2: native reader as formatted mode (landed)
  - Done: formatted mode shows the editor's text with syntax hidden, proportional prose, heading sizes, code styling, list markers, and quote insets; scroll sync, heading jumps, and table-of-contents following work through a source-to-reader offset map
  - Visual polish landed: inline-code capsules, code block panels, quote bars, heading rules, nested list indents, frontmatter property list, local images, and a centered 780 pt column
  - Remaining gaps, in priority order: code syntax highlighting; tables; remote images; find in formatted mode; heading commands in formatted mode
  - Related ids: `DEC-20260909-001`, `DEC-20260909-002`, `RSH-20260402-012`
- Slice 3: morph between the two stylings (landed)
  - Done: a mode switch measures every visible character in both text views, pairs them through the reader offset map, and slides one Core Animation layer per glyph from one styling to the other with a short glyph crossfade; syntax fades out, substituted markers fade in; beyond 1,500 paired characters the planner groups prose into per-word layers away from the viewport center; Reduce Motion, empty documents, and measurement failures fall back to the instant switch
  - Measured: planning a 4,000-character viewport takes about 40 ms in the debug test build; the 6,000-character case stays within the 3,000-layer budget
  - Related ids: `RSH-20260909-001`, `RSH-20260402-011`

- Slice 4a: typing and deleting in formatted mode through the source map (landed)
  - Done: the reader accepts input and refuses every direct change; each edit maps to a source range by character records and applies through the editor's own change path, so undo, highlighting, and the source sync are shared; the reader rebuilds by minimal replacement with the caret restored and no scroll jump; the syntax of the inline construct or heading at the caret shows in place and hides when the caret leaves; Enter starts a new paragraph in prose and a plain newline in code, lists, quotes, tables, HTML, and front matter; composition commits once on the same path; edits touching substituted constructs are refused with a beep
  - Measured: a 10,000-character document rebuilds in about 44 ms on a reveal change and 48 ms on a keystroke in the debug build
  - Related ids: `DEC-20260910-001`

- Slice 4b: the cursor crosses the morph (landed)
  - Done: a mode switch captures the source cursor from the outgoing surface; the incoming surface lands with its cursor at the same source position and keyboard focus, with or without a morph; the reader is built with the arriving cursor's reveal before the morph plans, so revealed syntax pairs with editor syntax and moves; Command-B and Command-I (and the Format menu) wrap the selection in formatted mode, keeping hidden syntax inside; italic uses `*` in both modes
  - Open: no toggle-off for bold or italic yet; wrapping already-wrapped text nests delimiters
  - Related ids: `DEC-20260910-001`, `RSH-20260909-001`

### Near Term

- Slice 4c: the syntax reveal animates
  - Done when: syntax appearing or disappearing around the caret fades in or out while the neighbouring glyphs on the affected lines slide to their new positions, using the same measured-position layers as the mode morph but scoped to the changed paragraph; a keystroke or caret move during the animation jumps it to its end state; Reduce Motion keeps the instant swap
  - Why: the operator asked for it after the first session with slice 4a; a popping reveal breaks the continuity the morph established
  - Related ids: `DEC-20260910-001`, `RSH-20260909-001`
- Slice 5: structural edits in formatted mode
  - Done when: Enter continues lists, deleting a bullet removes its marker, heading commands work, and images, frontmatter, and thematic breaks either route or stay refused with a visible reason
  - Related ids: `DEC-20260910-001`
- Initiative: tune the morph by eye on real documents: swap window, duration, per-word threshold, and how decorations (capsules, panels, bars) enter and leave
  - Why now: the feel is the product; the operator's first look on 2026-09-10 fixed a snapped animation, an empty first frame, and oversized paragraph gaps, and the remaining dials are still untouched
  - Dependencies: none
  - Related ids: `RSH-20260909-001`

### Mid Term

- Initiative: close the formatted-mode gap list: tables, images, code highlighting, find, heading commands, frontmatter
  - Why later: each is independent of the morph work and can land as its own slice
  - Dependencies: slice 2
  - Related ids: `DEC-20260909-002`

### Deferred But Accepted

- Initiative: broader block-aware editing affordances
  - Why deferred: source-mapped editing (slices 4 and 5) comes first; block objects only if routing through the map proves insufficient
  - Revisit trigger: slice 5 lands and a construct cannot be routed cleanly
  - Related ids: `DEC-20260409-003`
