# DEC-20260409-001: Repo Workflow And Evidence Policy
Opened: 2026-04-09 05-22-59 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: resolved-decisions.md

## Metadata

- Status: accepted
- Scope: repo workflow, research evidence standards, and provenance
- Related artifacts: `REPO.md`, `STATUS.md`, `LOG-20260409-001`

## Decision

Markfops will use a repo-native operating model with root truth docs, stable artifact ids, durable research memos, append-only decision records, append-only worklogs, and commit provenance trailers after the bootstrap migration commit.

## Context

Before this migration, the repo already relied on long-lived research coordination artifacts under a dedicated research workspace. That worked for the initial archaeology program, but it mixed durable findings, coordination state, open questions, and execution history inside one workspace and left provenance implicit.

## Options Considered

- Keep using a single research workspace as the de facto operating layer
- Move only a subset of the artifacts and leave the rest as legacy conventions
- Normalize the repo around explicit truth, plan, research, decision, and worklog surfaces

## Rationale

The research program already proved that Markfops benefits from persistent repo-local memory. The missing piece was a clear routing model. This decision codifies that:

- `SPEC.md`, `STATUS.md`, and `PLANS.md` are authoritative
- `INBOX.md` is scratch intake, not durable truth
- research requires stable `RSH-*` artifacts
- decisions require stable `DEC-*` artifacts
- work history requires stable `LOG-*` artifacts
- commit history should reinforce the same provenance graph

It also preserves the research evidence bar that made the earlier corpus useful: concrete code evidence, explicit fact-versus-interpretation separation, and consistent terminology.

## Consequences

- The retired research workspace is no longer the canonical control plane.
- Future work should route through the new root operating surfaces.
- Bootstrap or migration exceptions must be explicit in the commit message; later normal commits should carry compliant trailers.
- Contributors can use `.gitmessage.markfops` as a helper, `scripts/install-hooks.sh` to enable local enforcement, and the commit-standards CI workflow for remote re-validation.
