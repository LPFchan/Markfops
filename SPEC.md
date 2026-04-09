# Markfops Spec

This file is the canonical statement of what Markfops is supposed to be.
Keep it durable. Do not use it as a changelog, inbox, or weekly narrative.

## Identity

- Project: Markfops
- Canonical repo: this repository
- Project id: `markfops`
- Operator: yeowool
- Last updated: 2026-04-09
- Related decisions: `DEC-20260409-002`, `DEC-20260409-003`

## Product Thesis

Markfops is a lightweight, native macOS Markdown reader and editor. It should preserve Markdown as the trustworthy source of truth while delivering navigation, editing, preview, export, and document management through a first-class macOS experience instead of an Electron shell.

Markfops is also the host for an incremental native WYSIWYG Markdown engine program. That future engine should evolve out of the current source-first app, not replace it with a browser editor, tree-canonical store, or preview-owned document model.

## Primary User And Context

- Primary operator: a macOS user working directly with local Markdown files
- Primary environment: macOS 14+ with native document workflows
- Primary problem being solved: reading, editing, previewing, and organizing Markdown without sacrificing source fidelity or native feel
- Why this matters: users should be able to trust their Markdown files and still get fast navigation, rich preview, and app-quality ergonomics

## Primary Workspace Object

A Markdown document backed by canonical raw text in `Document.rawText`, presented through editor and preview surfaces, and managed across tabs, sidebar navigation, and file-system-backed persistence.

## Canonical Interaction Model

1. Open an existing Markdown file or create a new document.
2. Edit source in the native editor or switch the current tab between edit and preview mode.
3. Navigate via tabs, sidebar documents, and table of contents.
4. Save, save as, or export the document, including PDF export.
5. Reopen the app and continue with preserved document state and crash-safe behavior.

## Core Capabilities

- Capability: native Markdown editing
  - Why it exists: Markfops should feel like a real macOS editor, not a browser app wrapped in a shell.
  - What must remain true: editing stays AppKit-first and Markdown source remains trustworthy.
- Capability: faithful preview and document navigation
  - Why it exists: users need to inspect rendered structure and move quickly through long documents.
  - What must remain true: preview stays read-only, TOC stays derived from source, and navigation does not corrupt content.
- Capability: file-centric macOS workflows
  - Why it exists: Markdown files should behave like local documents, not opaque app-owned data.
  - What must remain true: drag and drop, open/save flows, proxy icon behavior, and document typing stay first-class.
- Capability: lightweight release and update pipeline
  - Why it exists: the app should remain easy to build, test, package, and distribute.
  - What must remain true: Xcode/XcodeGen workflows, GitHub Actions, Sparkle publishing assets, and release notes remain operable.

## Invariants

- Markdown source is the only persisted source of truth.
- The product is native macOS-first, not web-first.
- Preview and rendering must never silently rewrite or replace source content.
- The future engine must preserve stable semantic identity before promising smooth text-object or block-object motion.
- Editor and preview synchronization must be owned explicitly; ratio-only scrolling is a baseline, not the long-term correctness model.
- The repo keeps canonical truth in `SPEC.md`, `STATUS.md`, and `PLANS.md`, not only in chat history.

## Native WYSIWYG Direction

The accepted engine trajectory is a Markdown-canonical native editing system with a derived semantic block graph, durable block and inline-region identity, shared source-span mapping, a synchronization coordinator, and a transition coordinator.

The goal is not "make the preview editable." The goal is a native macOS writing surface that can move progressively from source editing toward richer semantic presentation while preserving Markdown round-trip fidelity.

The transition program is expected to support:

- viewport-aware motion between editor and preview presentations
- rigorous scroll anchoring across live edits, layout changes, mode switches, code blocks, tables, images, and semantic role changes
- modeled semantic transitions for headings, quotes, inline code, code blocks, lists, emphasis, links, and other supported Markdown constructs
- incremental parsing, identity matching, preview patching, and visible-region layout work before whole-document replacement

Accepted direction lives in `PLANS.md`; durable rationale lives in `DEC-20260409-002`, `DEC-20260409-003`, and `RSH-20260402-009`.

## Non-Goals

- Replacing Markdown storage with a block-canonical or tree-canonical persisted model
- Rebuilding the product as an Electron or browser-core application
- Treating preview rendering as an editable truth surface
- Shipping full Notion-like block editing before semantic identity, source spans, synchronization, and transition ownership are proven

## Main Surfaces

- Surface: native app target
  - Purpose: ship the macOS app itself
  - Notes: source lives under `Markfops/`, tests under `MarkfopsTests/`, and project generation under `project.yml`
- Surface: packaging and release assets
  - Purpose: produce appcast, release notes, and signed distribution metadata
  - Notes: packaging lives under `Packaging/`, Sparkle pages assets under `docs/`
- Surface: repo operating layer
  - Purpose: keep truth, plans, research, decisions, and worklogs legible over time
  - Notes: authoritative files live at repo root, under `research/`, and under `records/`

## Success Criteria

- Markfops remains a fast, trustworthy native Markdown app for macOS.
- Markdown round-trip fidelity and read-only preview safety remain intact.
- The future native WYSIWYG engine can be developed incrementally without abandoning the current product architecture.
- Editor/preview synchronization and mode-switch motion can be evaluated against stable semantic anchors rather than ad hoc pixels, headings, or scroll ratios alone.
