# DEC-20260409-002: Markfops Architecture Constraints
Opened: 2026-04-09 05-22-59 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: resolved-decisions.md

## Metadata

- Status: accepted
- Scope: product and engine architecture constraints
- Related research: `RSH-20260402-002`, `RSH-20260402-007`, `RSH-20260402-008`, `RSH-20260402-009`

## Decision

Markfops will preserve Markdown as the canonical persisted format, remain native macOS-first, and treat rigorous dual-view synchronization and semantic transition quality as first-class constraints for future engine work.

## Context

The research program compared Markfops with Milkdown, Intend, Inkdown, and SimpleBlockEditor. That work established that Markfops already has a viable native baseline, but it also exposed constraints that must not be compromised during future architecture changes.

## Options Considered

- Continue without explicit architectural constraints
- Adopt a web-first or tree-first editor model from a reference repo
- Codify the constraints discovered during research and treat them as durable design boundaries

## Rationale

The accepted research repeatedly converged on the same boundaries:

- `Document.rawText` is the current canonical document model.
- Stable identity does not yet exist for general semantic blocks or inline spans.
- Browser-DOM-centric editor state should not define Markfops' target architecture.
- Scroll synchronization between editor and preview is not a secondary refinement anymore.

Making these constraints explicit prevents future implementation work from drifting toward expedient but incompatible models.

## Consequences

- Future plans and code changes must preserve Markdown-first persistence.
- Reference repositories remain inputs to understanding, not transplant targets.
- Dual-view synchronization and semantic motion are part of the acceptance bar for the future engine.
- Decisions about block identity, preview updates, and block-aware editing must be evaluated against these constraints first.
