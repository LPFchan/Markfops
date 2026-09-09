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

- Outcome: the reader view becomes a second styling of the editor's own native text, with syntax hidden, proportional prose, styled headings, and inline-code capsules, while the web preview stays available until the native reader covers what users rely on.
- Why this is accepted: one text engine removes the two-engine coordination problems that stalled the April research; see `DEC-20260909-001`.
- Expected value: scroll synchronization becomes trivial, cross-view motion becomes possible, and the native WYSIWYG engine gets its rendering layer without a duplicate web pipeline.
- Preconditions: a per-character kind map derived from the existing cmark-gfm parse.
- Earliest likely start: now
- Related ids: `DEC-20260909-001`, `RSH-20260909-001`

### Measured-Position Text Morphing

- Outcome: switching between editor and reader stylings animates each visible glyph from its position in one styling to its position in the other, driven by Core Animation, following the approach validated in `RSH-20260909-001`.
- Why this is accepted: the spike showed the motion is cheap and looks right; the remaining questions are pairing through source spans and how far per-glyph splitting can scale.
- Expected value: the continuity the research program set out to achieve, without a font that interpolates between monospace and proportional forms.
- Preconditions: the native reader styling exists and the kind map identifies which source characters survive into it.
- Earliest likely start: after the native reader styling lands
- Related ids: `DEC-20260909-001`, `RSH-20260909-001`, `RSH-20260402-012`

### Deferred But Accepted: Block-Aware Native Editing

- Outcome: Markfops introduces more explicit block-aware editing only after the native reader and morphing foundations prove out.
- Why this is accepted: the research program identified block-aware editing as valuable, but too risky as the first migration step.
- Expected value: richer structural editing without abandoning Markdown-first persistence.
- Preconditions: native reader styling and morphing are stable.
- Earliest likely start: version 2 of the engine program
- Related ids: `DEC-20260409-003`, `RSH-20260402-006`, `RSH-20260402-009`

## Sequencing

Each slice must end with something visible in the app and its own tests.

### Near Term

- Slice 1: derive a per-character kind map from the existing cmark-gfm parse
  - Why now: cmark already exposes start and end positions for every node, including inline nodes, so this is the cheapest possible source of "which characters are syntax and which construct owns them"
  - Done when: the map feeds heading extraction (replacing the separate line scanner) and syntax highlighting, with tests covering headings, inline code, emphasis, links, and multi-byte text
  - Related ids: `DEC-20260909-001`, `IBX-20260409-001`, `IBX-20260409-002`
- Slice 2: native reader styling as a toggle
  - Why next: it is the reader view itself, without animation, and it exposes every gap against the web preview
  - Done when: the editor's text storage can be shown with syntax hidden, proportional prose, heading sizes, and code capsules, the toggle is reachable from the existing mode switch, and a written gap list against the web preview exists
  - Related ids: `DEC-20260909-001`, `RSH-20260402-012`
- Slice 3: morph between the two stylings
  - Why last: it needs both stylings and the kind map for pairing
  - Done when: a mode switch animates the visible region with no dropped frames on a document of a few thousand visible characters, using Core Animation, and the per-glyph versus per-word split is measured and chosen
  - Related ids: `RSH-20260909-001`, `RSH-20260402-011`

### Mid Term

- Initiative: native rendering of tables, images, code highlighting, and frontmatter property tables
  - Why later: these decide when the web reader can be removed from the reading path
  - Dependencies: slice 2 gap list
  - Related ids: `DEC-20260909-001`
- Initiative: decide the web view's remaining role
  - Why later: export and printing may keep using HTML; the reading path should not
  - Revisit trigger: the mid-term native rendering work closes the gap list
  - Related ids: `DEC-20260909-001`

### Deferred But Accepted

- Initiative: broader block-aware editing affordances
  - Why deferred: it should follow a proven native reader and morphing, not precede them
  - Revisit trigger: slices 1 through 3 land and stay stable
  - Related ids: `DEC-20260409-003`
