# Markfops Plans

This document contains accepted future direction only.
Do not put raw brainstorms or untriaged intake here.

## Planning Rules

- Only accepted future direction belongs here.
- Plans should be specific enough to guide implementation later.
- Architecture rationale should link to `DEC-*` records where possible.
- When a plan becomes current truth, reflect it into `SPEC.md` or `STATUS.md` and update this file.

## Approved Directions

### Repo Operating Model Adoption

- Outcome: Markfops uses root truth docs, stable artifact ids, worklogs, decisions, and commit provenance for future repo work.
- Why this is accepted: the repo already accumulated durable research and coordination artifacts, and they need one canonical home.
- Expected value: future product and research work becomes easier to route, audit, and hand off.
- Preconditions: bootstrap migration commit lands; commit-trailer workflow starts enforcing new provenance.
- Earliest likely start: now
- Related ids: `DEC-20260409-001`, `LOG-20260409-001`

### Semantic Scene Foundation For The Native WYSIWYG Engine

- Outcome: Markfops adds a markdown-derived semantic block layer with durable ids and source spans shared by editor and preview.
- Why this is accepted: the research program concluded that durable semantic identity is the smallest safe foundation for incremental native WYSIWYG work.
- Expected value: enables targeted preview updates, better synchronization anchors, and cleaner architecture for future editing features.
- Preconditions: implementation roadmap, risk register, and first spike selection are completed.
- Earliest likely start: after implementation framing closes
- Related ids: `DEC-20260409-002`, `DEC-20260409-003`, `RSH-20260402-009`

### Dedicated Synchronization And Transition Coordination

- Outcome: editor and preview alignment moves into explicit synchronization and transition coordinators with hybrid anchors, drift detection, and visible-region motion rules.
- Why this is accepted: rigorous dual-view behavior is now a first-class engine objective.
- Expected value: mode switches, live edits, and semantic transitions become more trustworthy and visually coherent.
- Preconditions: semantic block ids and source-span mapping are available.
- Earliest likely start: after the semantic scene foundation exists
- Related ids: `DEC-20260409-003`, `RSH-20260402-009`, `RSH-20260402-011`, `RSH-20260402-012`, `RSH-20260402-013`

### Deferred But Accepted: Block-Aware Native Editing

- Outcome: Markfops introduces more explicit block-aware editing only after the semantic scene, synchronization, and transition foundations prove out.
- Why this is accepted: the research program identified block-aware editing as valuable, but too risky as the first migration step.
- Expected value: richer structural editing without abandoning Markdown-first persistence.
- Preconditions: v1 semantic and synchronization infrastructure is stable.
- Earliest likely start: version 2 of the engine program
- Related ids: `DEC-20260409-003`, `RSH-20260402-006`, `RSH-20260402-009`

## Sequencing

### Near Term

- Initiative: complete implementation framing
  - Why now: roadmap, motion strategy, transition coverage, and risk framing are still incomplete
  - Dependencies: none beyond the current research corpus
  - Related ids: `RSH-20260402-010`, `RSH-20260402-011`, `RSH-20260402-012`, `RSH-20260402-013`
- Initiative: choose the first implementation spike
  - Why now: the research work has converged enough to move from archaeology to execution
  - Dependencies: implementation framing completion
  - Related ids: `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`

### Mid Term

- Initiative: ship semantic block identity and targeted preview update infrastructure
  - Why later: it depends on the first implementation spike and validation results
  - Dependencies: semantic scene design acceptance
  - Related ids: `DEC-20260409-003`

### Deferred But Accepted

- Initiative: broader block-aware editing affordances
  - Why deferred: it should follow proven semantic identity and synchronization infrastructure, not precede it
  - Revisit trigger: semantic scene and dual-view coordination land successfully
  - Related ids: `DEC-20260409-003`
