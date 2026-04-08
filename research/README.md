# Research

This directory stores curated research memos for Markfops.

## Naming

Create one file per reusable exploration:

- `RSH-YYYYMMDD-NNN-short-title.md`

## When To Create One

Create an `RSH-*` memo when a session produces learning worth future retrieval.

Do not create one for:

- raw work trace that belongs in `records/agent-worklogs/`
- casual brainstorm fragments that still belong in `INBOX.md`

## Required Opening

Each memo should begin with:

- `# RSH-YYYYMMDD-NNN: <Short Research Title>`
- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

Migrated memos may also include the original path for continuity.

## Default Shape

- Metadata
- Research question
- Why this belongs to this repo
- Findings
- Promising directions
- Dead ends or rejected paths
- Recommended routing

Use that section order by default unless the research genuinely needs a different structure.

## Canonical Example

```md
# RSH-20260409-001: Routing Research Findings Into Markfops Artifacts

Opened: 2026-04-09 09-30-00 KST
Recorded by agent: agent-example-001

## Metadata

- Status: completed
- Question: Where should Markfops store reusable architecture findings versus execution trace?
- Trigger: IBX-20260409-001
- Related ids: IBX-20260409-001, DEC-20260409-001

## Research Question

What is the safest default routing pattern for architecture findings discovered during implementation work?

## Why This Belongs To This Repo

Markfops has an active architecture program around a future native WYSIWYG engine. Reusable findings need a durable home that stays separate from truth docs and worklogs.

## Findings

- Reusable architecture findings belong in `research/` as `RSH-*` memos.
- Accepted current state belongs in `STATUS.md`, not in research.
- Accepted future direction belongs in `PLANS.md`.
- Run history and file-touch trace belong in `records/agent-worklogs/`.

## Promising Directions

- Keep research memos focused on reusable conclusions and routing guidance.
- Link research memos to `DEC-*` records when findings become accepted direction.

## Dead Ends Or Rejected Paths

- Dumping command logs into research was rejected because it turns reusable findings into noisy transcripts.
- Treating research as a substitute for `PLANS.md` was rejected because accepted direction needs its own canonical surface.

## Recommended Routing

- Store reusable findings here.
- Reflect accepted current-state changes into `STATUS.md`.
- Reflect accepted future direction into `PLANS.md`.
- Record execution history in `records/agent-worklogs/`.
```

## Current Corpus

- `RSH-20260402-001` preserves the research-program charter and methodology that survived the migration out of the retired research workspace.
- `RSH-20260402-002` through `RSH-20260402-013` preserve the accepted baseline, reference deep dives, synthesis docs, and framing stubs for the native WYSIWYG engine program.

## Local Notes

- Keep reusable findings here, not raw execution logs.
- Route coordination state into `STATUS.md`, `PLANS.md`, `INBOX.md`, `DEC-*`, and `LOG-*` instead of recreating a parallel control plane inside `research/`.
- Treat `ref/` repositories as specimens, not dependencies.
