# DEC-20260409-003: Native WYSIWYG Target Architecture Direction
Opened: 2026-04-09 05-22-59 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Derived from legacy file: resolved-decisions.md

## Metadata

- Status: accepted
- Scope: future engine architecture direction
- Related research: `RSH-20260402-007`, `RSH-20260402-008`, `RSH-20260402-009`

## Decision

The target direction for Markfops' native WYSIWYG engine is a Markdown-canonical architecture with a derived semantic block graph, durable semantic identity, and dedicated synchronization and transition coordinators shared by editor and preview.

## Context

The comparison and transferability work ruled out tree-first canonical state, content-derived ids, passive preview ownership, and full-document preview reload as the steady-state model for future editor work.

## Options Considered

- Keep the current split architecture and layer more ad hoc hooks on top
- Replace Markdown-first editing with a tree-first or block-first canonical model
- Add a derived semantic scene and explicit coordination subsystems while keeping Markdown canonical

## Rationale

The accepted research established that Markfops needs more structure than its current whole-document preview path, but not a replacement for Markdown-first truth. A derived semantic scene with durable ids creates a safe bridge between:

- source mapping and invalidation
- editor and preview coordination
- visible-region transitions
- later block-aware editing

Explicit synchronization and transition coordinators keep scroll ownership and motion policy out of renderer-local hacks.

## Consequences

- Version 1 engine work should prioritize semantic parse services, durable block ids, source spans, targeted preview updates, and hybrid viewport anchors.
- Broader block-aware editing should remain a later phase.
- Any implementation spike that undermines Markdown-first persistence or native editing quality should be rejected.
