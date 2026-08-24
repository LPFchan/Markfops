# Markfops Status

This document tracks current operational truth.
Update it when the project's real state changes.
Do not use it as a transcript or a scratchpad.

## Snapshot

- Last updated: 2026-08-24
- Overall posture: `active`
- Current focus: stabilize and validate the native app for the `0.1.0` release
- Highest-priority blocker: final release smoke testing and packaging validation are still pending
- Next operator decision needed: decide when the stabilized native app is ready to tag as `0.1.0`
- Related decisions: `DEC-20260409-001`, `DEC-20260409-002`, `DEC-20260409-003`, `DEC-20260410-001`

## Current State Summary

Markfops is a working native macOS Markdown app with XcodeGen project generation, GitHub Actions build and release workflows, Sparkle publishing assets, and a meaningful research corpus for a future native WYSIWYG engine. Each document window now owns its own tabs, while an app-level coordinator routes external files, tab transfers, close handling, and recovery across windows. External Markdown files join the most recently active window, and reopening a file focuses its existing tab instead of creating another copy. Existing scenes accept Finder and Dock file events, and simultaneous scene creation cannot bind multiple windows to the same tab catalog. Each window keeps a file watcher only for its active document; inactive documents are checked and reloaded when selected. Multi-file opens load every requested document before selecting the final tab, preventing watcher and rendering churn from exhausting the process file-descriptor limit. The active document's table of contents opens by default in the sidebar. Each document keeps its content scroll position across tab switches, while manually scrolling the sidebar pauses table-of-contents following until content navigation resumes it. In edit mode, table-of-contents following uses the source position at the viewport center, so wrapped lines do not make the highlighted heading drift away from the visible content. Clicking a table-of-contents heading highlights its exact source line, including in documents containing emoji, Korean, or other text whose AppKit offsets differ from Swift character counts. Sidebar rows use cached document metadata, table-of-contents rows are derived in one pass, and scroll geometry no longer rebuilds the sidebar, keeping navigation responsive with dozens of open documents. Edit-mode syntax highlighting is stable across view and configuration updates, undo and redo history belongs to each document and survives tab or window moves, and the release workflow gates packaging on the full test suite. The immediate product focus is validating this baseline for the first `0.1.0` release.

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
- Date: 2026-08-24
  - Change: document handling gained explicit per-window ownership, coordinated external opens and recovery, transferable tabs, document-scoped undo history, active-document-only file watching, and batched multi-file opening; edit-mode syntax highlighting became stable; CI began enforcing renderer, highlighting, undo, and watcher tests
  - Why it matters: new windows and detached tabs remain independent, external files join the active window without duplicate state, large file sets no longer exhaust the process file-descriptor limit, undo and redo survive editor recreation and document moves, editor colors no longer disappear during view updates, and regressions now fail the build
  - Related ids: none yet

## Active Blockers And Risks

- Blocker or risk: first implementation spike is not selected yet
  - Effect: the project can continue refining architecture without turning accepted direction into code
  - Owner: operator plus orchestrator
  - Mitigation: finish the framing docs and route the remaining open questions into a small first spike
  - Related ids: `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`, `IBX-20260409-004`

## Immediate Next Steps

- Next: complete the `0.1.0` release smoke test and packaging validation
  - Owner: operator plus release agent
  - Trigger: the multi-window, tab-transfer, syntax-highlighting, and undo fixes are merged
  - Related ids: `STATUS.md`
- Next: finish `RSH-20260402-010` through `RSH-20260402-013`
  - Owner: orchestrator with operator review
  - Trigger: `0.1.0` release stabilization is complete
  - Related ids: `RSH-20260402-010`, `RSH-20260402-011`, `RSH-20260402-012`, `RSH-20260402-013`
- Next: choose and execute the first implementation spike
  - Owner: operator plus implementation agent
  - Trigger: framing docs and open intake are synthesized into a bounded task
  - Related ids: `PLANS.md`, `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`
