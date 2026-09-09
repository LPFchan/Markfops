# DEC-20260910-001: Formatted Editing Returns Through The Source Map
Opened: 2026-09-10 05-10-00 KST
Recorded by agent: claude-torph-spike-20260909

## Metadata

- Status: accepted
- Deciders: operator
- Scope: product direction and engine architecture; supersedes the read-only consequence of commit `1ec26e6` (2026-04-02) and the read-only wording in `SPEC.md`
- Related ids: `DEC-20260909-001`, `DEC-20260909-002`, `DEC-20260409-003`, `RSH-20260909-001`, `IBX-20260409-004`

## Decision

Formatted mode becomes editable again. Every edit made in formatted mode is translated through the reader's per-character source map into an edit of the exact Markdown source range, applied to the document as a normal source edit with shared undo. The reader is rebuilt from the changed source; its displayed text is never written back to the file.

Syntax is revealed Typora-style: the Markdown syntax of the construct that holds the text cursor is shown in place as real characters, and hides again when the cursor leaves. Revealed syntax is mapped one-to-one to the source, so it morphs between modes like any other character.

The text cursor carries across a mode switch. Switching modes places the cursor at the same source position in the incoming surface, ready to type.

Constructs the map cannot route yet (list markers, images, frontmatter, thematic breaks, raw tables and HTML) refuse the edit instead of guessing. They gain routing in later slices.

## Context

Markfops shipped a contentEditable web preview on 2026-03-23. Its edits synced back by writing the rendered article's `innerText` into the source, which dropped heading marks, emphasis, link targets, and code fences. The operator made the preview read-only on 2026-04-02 and opened the native WYSIWYG research program the same day, with "avoids the preview-to-source corruption class of bugs by design" as an objective. The native reader (`DEC-20260909-001`) now knows the source range of every character it shows, which is the capability the April version lacked.

## Options Considered

- Keep formatted mode read-only and add editing affordances only in monospace mode
- Hide syntax inside the monospace editor itself (single-view Typora clone) instead of editing the reader
- Edit the reader and route each edit through the source map to the exact source range, with cursor-local syntax reveal

## Rationale

The operator wants to write in the formatted view; that was the original goal of the March feature. Routing through the source map keeps Markdown as the only truth and shares undo with monospace mode, so the corruption class cannot return. Cursor-local reveal, chosen by the operator over a fixed inside/outside rule, makes the edit position unambiguous at the one place edits happen. A single-view approach would discard the two-mode dynamic and the morph that just landed.

## Consequences

- `SPEC.md` no longer promises a read-only preview. The invariant that rendering never silently rewrites source content stays and is what the routing guarantees.
- Slices land in order: typing and deleting through the map with syntax reveal and cursor restore; cursor carried across the morph with revealed syntax morphing; then list markers, Enter continuation, heading and emphasis commands, and the remaining substituted constructs.
- Each construct that gains routing needs tests that assert the exact source edit produced.
- `IBX-20260409-004` (how far the `NSTextView` editor stretches before block-aware editing) now has a concrete answer under test: as far as the source map can route.
