# Research

This directory stores curated research memos, not raw execution logs.

## Naming

Create one file per reusable exploration:

- `RSH-YYYYMMDD-NNN-short-title.md`

## When To Create One

Create an `RSH-*` memo when a session produces learning worth future retrieval.

Do not create one for:

- raw work trace that belongs in commit history or Off-Git runtime memory
- casual brainstorm fragments that still belong in `INBOX.md`

## Required Opening

Each memo should begin with:

- `# RSH-YYYYMMDD-NNN: <Short Research Title>`
- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

## Markfops Provenance Note

Migrated memos may also include the original path for continuity.

## Minimum Content

A research memo should usually make these things recoverable:

- what question or area was explored
- the findings worth preserving
- any important rejected paths, open questions, or follow-up routes

The exact section names and order can vary by project.

## Suggested Shapes

Any of these are acceptable when they fit the repo better:

- question -> findings -> next steps
- topic -> evidence -> conclusion
- exploration notes -> recommendations
- short memo with lightweight headings

Keep the memo normalized and readable, but do not force one house style across every repo.

## Markfops-Useful Shapes

These additional shapes are already used by the migrated native WYSIWYG research corpus:

- specimen archaeology -> observed facts -> architectural interpretation -> Markfops judgment
- research charter -> objective -> principles -> methods -> quality bar
- pending brief -> current state -> questions to answer -> inputs -> done when

## Current Corpus

- `RSH-20260402-001` preserves the research-program charter and methodology that survived the migration out of the retired research workspace.
- `RSH-20260402-002` through `RSH-20260402-009` preserve the accepted baseline, reference deep dives, synthesis docs, and target architecture for the native WYSIWYG engine program.
- `RSH-20260402-010` through `RSH-20260402-013` are pending framing briefs. They preserve the open implementation-framing topics without pretending that roadmap, motion, transition, or risk decisions are complete.

## Local Notes

- Keep reusable findings here, not raw execution logs.
- Route coordination state into `STATUS.md`, `PLANS.md`, `INBOX.md`, `DEC-*`, and `LOG-*` instead of recreating a parallel control plane inside `research/`.
- Treat `ref/` repositories as specimens, not dependencies.
