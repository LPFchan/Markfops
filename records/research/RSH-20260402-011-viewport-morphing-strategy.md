# RSH-20260402-011: Viewport Morphing Strategy
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: viewport-morphing-strategy.md

Status: pending framing brief

## Objective

Define how visible text and block objects morph between editor and preview presentations at 60 fps, with 120 fps as a stretch goal.

## Current State

The old research plan asked for a viewport morphing strategy, but no dedicated strategy has been accepted yet. The completed target architecture names a Transition Coordinator and Synchronization Coordinator; this memo should become the measurable design for those parts.

## Questions To Answer

- What counts as a morphable text object, inline semantic segment, block, row, or preview DOM element?
- Which ids stay stable across editor styling, preview rendering, heading promotion, quote promotion, code styling, list wrapping, and source edits?
- Which geometry snapshots must editor and preview expose before and after an update?
- Which transitions are direct interpolation, which are hybrid motion plus discrete swap, and which should not animate?
- How do selection, caret, IME composition, viewport clipping, scroll momentum, WebKit layout timing, and AppKit text layout affect correctness?

## Strategy Constraints

- Animation policy belongs in the Transition Coordinator, not inside the Markdown renderer, preview DOM script, editor text view, or scroll adapter.
- Synchronization policy belongs in the Synchronization Coordinator and should use semantic anchors plus local offset and continuous ratio.
- Motion must be viewport-first. The full document does not need animation-grade geometry.
- Screenshot cross-fades are not a substitute for semantic identity and measured geometry.

## Measurements Needed

- dropped frames during mode switches
- parser and identity-matching time after local edits
- editor layout time for visible blocks
- preview DOM patch time and WebKit layout completion time
- number of blocks or inline regions whose geometry is captured per transition
- scroll-anchor drift before and after coordinator correction

## Open Risks

- editor and preview use different layout engines today
- whole-document preview replacement destroys DOM continuity
- headings have narrow preview-side transition code, but general semantic identity does not exist yet
- source editing, selection, IME, undo, and syntax tokens may fight preview-like semantic presentation
