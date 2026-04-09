# RSH-20260402-013: Risk Register
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: risk-register.md

Status: pending framing brief

## Current State

This risk register is a pending framing memo. It should be completed before the first engine spike is chosen and should stay focused on risks discovered by the archaeology and target-architecture work.

## Fidelity Risks

- Markdown source can be corrupted if preview-side DOM edits, semantic-block transforms, or serializers become canonical by accident.
- Hiding syntax tokens can break selection, copy/paste, undo, IME, and exact round-trip expectations if the source mapping is weak.
- Content-derived heading slugs are useful for navigation but unsafe as durable semantic identity.

## Performance Risks

- Whole-document Markdown-to-HTML preview replacement is too broad for smooth live synchronization and semantic transitions.
- Full reparsing and full attributed-string restyling after local edits may erase identity and exceed the visible-interaction budget.
- WebKit layout timing and AppKit text layout timing may not be available early enough for same-frame cross-presentation animation.

## AppKit and TextKit Risks

- Native editing quality can regress if semantic overlays, hidden tokens, or block rows fight `NSTextView`, selection, undo, input method composition, accessibility, or standard text commands.
- One-text-view-per-block designs may simplify block identity but risk text-system behavior, selection continuity, and memory overhead.

## Motion Risks

- Screenshot cross-fades can look smooth while hiding identity, source-mapping, and synchronization bugs.
- Typography, block margins, code blocks, images, tables, and wrapped lists can make editor and preview geometry diverge enough that ratio-only sync drifts.
- Transitions may be visually dishonest when syntax appears or disappears, lines rewrap, or containers are inserted.

## Migration Risks

- Replacing the current editor before semantic identity and source spans are proven would endanger the working app.
- Copying a tree-first model from Milkdown, Inkdown, or SimpleBlockEditor would undermine Markdown-first persistence.
- Shipping target architecture as a large rewrite would make it hard to protect the current open/edit/preview/save/export/release baseline.
