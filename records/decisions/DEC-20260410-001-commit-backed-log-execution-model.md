# DEC-20260410-001: Commit-Backed LOG Execution Model
Opened: 2026-04-10 23-01-33 KST
Recorded by agent: codex-markfops-logmig

## Metadata

- Status: accepted
- Scope: repo workflow, execution history, and provenance
- Related artifacts: `REPO.md`, `STATUS.md`, `LOG-20260410-230133-logmig`

## Decision

Markfops will use git commit history as the canonical execution history through structured commit-backed `LOG-*` records. The legacy markdown execution-history surface is retired.

## Context

The repo already had durable research memos, decision records, and commit provenance enforcement, but execution history still lived in a separate markdown execution-history surface. That created a second lookup path for the same kind of information and made the repo's memory story harder to explain.

## Options Considered

- Keep the markdown execution-history surface as the primary execution-history surface
- Run a hybrid system with both markdown execution history and commit-backed records
- Retire the markdown execution-history surface and make commit history the canonical execution record

## Rationale

Commit history is already the durable lineage graph for landed work. Using commit-backed `LOG-*` records keeps execution history connected to actual changes while avoiding a parallel markdown archive that would need special lookup rules.

- execution lineage stays recoverable through commits, trailers, and commit bodies
- new work no longer needs a second markdown file layer just to preserve provenance
- release automation and agent workflows can land execution records directly in git

## Consequences

- the legacy markdown execution-history surface is removed from the repo
- live docs should refer to commit-backed `LOG-*` records rather than markdown execution history
- future commits must continue to satisfy the commit-backed provenance contract
- the legacy handoff content is preserved in commit history and repo docs instead of a separate file layer
