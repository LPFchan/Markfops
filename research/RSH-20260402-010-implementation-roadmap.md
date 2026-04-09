# RSH-20260402-010: Implementation Roadmap
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: implementation-roadmap.md

Status: pending framing brief

## Current State

The implementation roadmap has not been accepted yet. Completed archaeology and synthesis point toward a semantic-scene foundation, but the first implementation spike still needs to be selected and sequenced against test, performance, synchronization, and migration risk.

## Roadmap Question

What is the smallest ordered set of implementation spikes that can prove Markdown-first semantic identity, dual-view synchronization, and viewport-safe transitions without destabilizing the current native editor?

## Inputs To Use

- `RSH-20260402-002`: current Markfops baseline and its whole-document preview path
- `RSH-20260402-007`: comparison synthesis
- `RSH-20260402-008`: transferability buckets
- `RSH-20260402-009`: accepted target architecture direction
- `IBX-20260409-001` through `IBX-20260409-004`: unresolved implementation-framing questions

## Draft Shape To Produce

- Phase 1: semantic parse service, source spans, durable block ids, and tests for identity preservation
- Phase 2: block-id-emitting preview, targeted preview update experiment, and hybrid scroll-anchor prototype
- Phase 3: visible-region transition coordinator experiment for a small Markdown construct set
- Validation gates: Markdown round-trip tests, identity-stability tests, editor/preview drift instrumentation, preview patch correctness, frame-time sampling, and regression coverage for current open/edit/save/export flows

## Not Decided Yet

- the first concrete spike
- the minimum semantic block taxonomy
- the identity matching heuristic after edits
- the first construct set for transition validation
