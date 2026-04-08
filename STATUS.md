# Markfops Status

This document tracks current operational truth.
Update it when the project's real state changes.
Do not use it as a transcript or a scratchpad.

## Snapshot

- Last updated: 2026-04-09
- Overall posture: `active`
- Current focus: strict repo-template adoption plus implementation framing for the native WYSIWYG engine
- Highest-priority blocker: the implementation roadmap, semantic transition coverage, and risk register are still incomplete
- Next operator decision needed: choose the first implementation spike after the framing docs are finished
- Related decisions: `DEC-20260409-001`, `DEC-20260409-002`, `DEC-20260409-003`

## Current State Summary

Markfops already ships as a native macOS Markdown app with XcodeGen project generation, GitHub Actions build and release workflows, Sparkle publishing assets, and a meaningful research corpus for a future native WYSIWYG engine. The reference deep dives and synthesis work are complete enough to support implementation framing, but the repo was only now normalized into root truth docs, decision records, worklogs, and stable research memos.

## Active Phases Or Tracks

### Core App Baseline

- Goal: preserve and ship the current native Markdown editor, preview, navigation, and packaging pipeline
- Status: `in progress`
- Why this matters now: the current product remains the foundation that future engine work must not destabilize
- Current work: maintain the existing app structure, tests, release workflows, and Sparkle assets while research and planning continue
- Exit criteria: baseline app workflows remain healthy during repo and architecture work
- Dependencies: `Markfops/`, `MarkfopsTests/`, `project.yml`, GitHub Actions
- Risks: future engine experiments could compromise Markdown fidelity or native feel if they skip the accepted constraints
- Related ids: `RSH-20260402-002`, `DEC-20260409-002`

### Native WYSIWYG Engine Research And Framing

- Goal: convert completed archaeology into an implementation-ready architecture and first spike
- Status: `in progress`
- Why this matters now: the repo has enough accepted research to move from exploration toward execution
- Current work: complete the roadmap, transition coverage, morphing strategy, risk framing, and first-spike selection
- Exit criteria: implementation framing docs are filled in and the first concrete spike is chosen
- Dependencies: `RSH-20260402-007` through `RSH-20260402-013`
- Risks: unresolved questions around semantic identity, invalidation, and synchronization can still create drift in early implementation choices
- Related ids: `DEC-20260409-002`, `DEC-20260409-003`, `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`, `IBX-20260409-004`

### Repo Operating Model Adoption

- Goal: make root truth docs, research memos, worklogs, decisions, and commit provenance the canonical repo workflow
- Status: `in progress`
- Why this matters now: the repo already depends on long-lived research and coordination artifacts, and those need one stable home
- Current work: migrate the retired research workspace into root surfaces, add stable IDs, and introduce local hook plus CI commit provenance enforcement
- Exit criteria: migration commit lands, the retired research workspace is superseded, local hooks can be installed, and remote provenance checks are active in CI
- Dependencies: `REPO.md`, `.githooks/commit-msg`, `.gitmessage.markfops`, `scripts/check-commit-standards.sh`, `scripts/check-commit-range.sh`, `scripts/install-hooks.sh`, `.github/workflows/commit-standards.yml`
- Risks: future commits may omit trailers until the migration commit is merged and the new workflow becomes routine
- Related ids: `DEC-20260409-001`, `LOG-20260409-001`

## Recent Changes To Project Reality

- Date: 2026-04-02
  - Change: the research program added rigorous two-view scroll synchronization as a first-class objective
  - Why it matters: future architecture work now has a higher bar than simple preview parity
  - Related ids: `DEC-20260409-002`
- Date: 2026-04-03
  - Change: reference deep dives and synthesis artifacts were completed and accepted
  - Why it matters: implementation framing can begin without reopening the full archaeology pass
  - Related ids: `RSH-20260402-003` through `RSH-20260402-009`
- Date: 2026-04-09
  - Change: canonical repo truth moved to root operating surfaces and records
  - Why it matters: future work now has stable routing, provenance expectations, and durable artifact locations
  - Related ids: `DEC-20260409-001`, `LOG-20260409-001`

## Active Blockers And Risks

- Blocker or risk: first implementation spike is not selected yet
  - Effect: the project can continue refining architecture without turning accepted direction into code
  - Owner: operator plus orchestrator
  - Mitigation: finish the framing docs and route the remaining open questions into a small first spike
  - Related ids: `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`, `IBX-20260409-004`
- Blocker or risk: commit provenance is documented before it has gone through a merged workflow cycle
  - Effect: early adopters may forget trailers or local template usage
  - Owner: operator plus future contributors
  - Mitigation: use the bootstrap exception once, then rely on the CI checker and local template
  - Related ids: `DEC-20260409-001`, `LOG-20260409-001`

## Immediate Next Steps

- Next: finish `RSH-20260402-010` through `RSH-20260402-013`
  - Owner: orchestrator with operator review
  - Trigger: repo migration is complete
  - Related ids: `RSH-20260402-010`, `RSH-20260402-011`, `RSH-20260402-012`, `RSH-20260402-013`
- Next: choose and execute the first implementation spike
  - Owner: operator plus implementation agent
  - Trigger: framing docs and open intake are synthesized into a bounded task
  - Related ids: `PLANS.md`, `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`
