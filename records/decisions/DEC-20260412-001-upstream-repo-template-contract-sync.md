# DEC-20260412-001: Current Upstream Repo-Template Contract Sync
Opened: 2026-04-12 09-23-10 KST
Recorded by agent: codex-markfops-upsync

## Metadata

- Status: accepted
- Scope: repo contract, local divergence handling, and commit provenance enforcement
- Related artifacts: `REPO.md`, `AGENTS.md`, `skills/README.md`, `skills/repo-orchestrator/SKILL.md`, `.github/workflows/commit-standards.yml`

## Decision

Markfops will keep the current upstream repo-template contract verbatim in the governed surfaces and keep repo-specific material only in explicit local-divergence sections or local extensions.

## Context

The repo already adopted repo-template, but the governed contract files and enforcement helpers had accumulated local wording and a few local conveniences. The repo needed a clean sync to the current upstream contract without losing the Markfops-specific commands, paths, and project notes that still matter locally.

## Options Considered

- Keep the existing local wording and mixed contract surfaces
- Replace the governed surfaces with the current upstream repo-template wording and isolate local details separately
- Rebuild the repo contract around a new Markfops-only policy layer

## Rationale

Keeping the upstream contract verbatim reduces drift and makes future migrations easier to compare against the source template. Isolating local notes and stronger local checks in explicit divergence sections keeps the repo-specific behavior visible without rewriting the upstream rules in Markfops phrasing.

- governed docs stay aligned with the current template source
- local commands and project notes remain available where they are useful
- stronger local enforcement can remain explicit instead of hidden inside rewritten policy prose

## Consequences

- `REPO.md`, `AGENTS.md`, and the skills layer track the current upstream wording
- Markfops-specific notes live in labeled local-divergence sections
- the commit standards hook and range checker remain active locally
- remote enforcement stays on the same upstream contract through CI
