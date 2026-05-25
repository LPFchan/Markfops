# RSH-20260402-012: Semantic Transition Coverage
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: semantic-transition-coverage.md

Status: pending framing brief

## Current State

The research plan requires transition coverage for Markdown constructs, but Markfops has not accepted construct-by-construct behavior yet. Use this memo to classify the first supported semantic transitions before implementing generalized motion.

## Classification Question

For each Markdown construct, decide whether the transition should be continuously morphable, hybrid morphable, or discrete-only; then record what identity stays stable, what geometry changes, which syntax tokens remain editable or visible, and which renderer owns each presentation detail.

## Initial Hypothesis To Validate

- Continuously morphable candidates: paragraph-to-heading typography, quote marker emphasis, inline-code styling, emphasis/strong styling, and link text styling when text identity is unchanged.
- Hybrid morphable candidates: fenced code block creation, list wrapping, task-list marker changes, table preview, and transitions that add containers, backgrounds, gutters, or multi-line reflow.
- Discrete-only candidates: transitions that fundamentally change editability, require full WebKit re-layout before geometry can be trusted, or would fake continuity across unrelated source spans.

## Construct Notes

### Headings

The current preview has a narrow line-based heading-promotion morph. Future behavior should reuse semantic block or inline ids, not heading text or DOM position alone.

### Quotes

Classify paragraph-to-blockquote as a block-level or line-level transition. Decide how the quote marker, inset, border, background, and text baseline animate.

### Inline Code

Classify syntax-token hiding, monospace font transition, background capsule drawing, baseline shift, and token editability.

### Code Blocks

Expect a hybrid transition: fenced code blocks alter container geometry, syntax styling, scrolling behavior, and typography beyond one inline span.

### Lists

Classify marker identity, continuation behavior, indentation, checkbox/task-list state, wrapped-line geometry, and multi-item container continuity.

### Emphasis

Decide whether emphasis and strong are pure attributed-text style transitions in the editor projection, preview projection, or both.

### Links

Preserve identity for visible link text separately from destination URL and syntax-token presentation.

### Tables

Treat tables as high risk until layout, hit-testing, source mapping, and preview/editor geometry can be measured.
