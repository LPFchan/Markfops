# Markfops Status

This document tracks current operational truth.
Update it when the project's real state changes.
Do not use it as a transcript or a scratchpad.

## Snapshot

- Last updated: 2026-04-10
- Overall posture: `active`
- Current focus: implementation framing for the native WYSIWYG engine
- Highest-priority blocker: the implementation roadmap, semantic transition coverage, and risk register are still incomplete
- Next operator decision needed: choose the first implementation spike after the framing docs are finished
- Related decisions: `DEC-20260409-001`, `DEC-20260409-002`, `DEC-20260409-003`, `DEC-20260410-001`

## Current State Summary

Markfops already ships as a native macOS Markdown app with XcodeGen project generation, GitHub Actions build and release workflows, Sparkle publishing assets, and a meaningful research corpus for a future native WYSIWYG engine. The reference deep dives and synthesis work are complete enough to support implementation framing, and the repo is now normalized into root truth docs, decision records, commit-backed execution history, and stable research memos.

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
  - Related ids: `DEC-20260409-001`, `LOG-20260410-230133-logmig`
- Date: 2026-04-10
  - Change: commit-backed `LOG-*` execution history replaced the legacy markdown execution-history surface
  - Why it matters: execution records now live in git history, the retired markdown surface no longer exists, and provenance stays recoverable without a parallel file layer
  - Related ids: `DEC-20260410-001`, `LOG-20260410-230133-logmig`

## Active Blockers And Risks

- Blocker or risk: first implementation spike is not selected yet
  - Effect: the project can continue refining architecture without turning accepted direction into code
  - Owner: operator plus orchestrator
  - Mitigation: finish the framing docs and route the remaining open questions into a small first spike
  - Related ids: `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`, `IBX-20260409-004`

## Immediate Next Steps

- Next: finish `RSH-20260402-010` through `RSH-20260402-013`
  - Owner: orchestrator with operator review
  - Trigger: repo migration is complete
  - Related ids: `RSH-20260402-010`, `RSH-20260402-011`, `RSH-20260402-012`, `RSH-20260402-013`
- Next: choose and execute the first implementation spike
  - Owner: operator plus implementation agent
  - Trigger: framing docs and open intake are synthesized into a bounded task
  - Related ids: `PLANS.md`, `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`
