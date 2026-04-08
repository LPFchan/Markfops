# Agent Worklogs

This directory stores execution history for runs, migrations, implementation passes, and subagent workstreams.

## Naming

Create one file per run or workstream:

- `LOG-YYYYMMDD-NNN-short-title.md`

## Worklog Hygiene

- Worklogs are append-only.
- If a correction is needed, append a new note rather than erasing history.
- Do not use worklogs as a substitute for `SPEC.md`, `STATUS.md`, or decision records.

## Required Opening

Each worklog should begin with:

- `# LOG-YYYYMMDD-NNN: <Short Run Or Task Title>`
- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

## Default Shape

- Metadata
- Task
- Scope
- Timestamped entries with actions, files touched, checks run, outputs, blockers, and next steps

Use that structure by default so worklogs stay scan-friendly and comparable across runs.

## Canonical Example

```md
# LOG-20260409-001: Normalize Repo-Template Entry Points

Opened: 2026-04-09 10-00-00 KST
Recorded by agent: agent-example-001

## Metadata

- Run type: orchestrator
- Goal: add thin agent entrypoints and normalize local writing guides
- Related ids: DEC-20260409-001

## Task

Bring the repo's enforcement entrypoints and artifact guides into closer alignment with repo-template without losing Markfops-specific truth.

## Scope

- In scope: `AGENTS.md`, `CLAUDE.md`, local surface guides, and minimal shape fixes to touched docs
- Out of scope: full-repo artifact rewrites

## Entry 2026-04-09 10-05-00 KST

- Action: compared the current repo docs with the reference repo-template surfaces
- Files touched: none
- Checks run: `find . -maxdepth 3 -type f | sort`
- Output: identified missing entrypoint files and lighter-than-template local guides
- Blockers: none
- Next: update the enforcement layer and touched guides

## Entry 2026-04-09 10-18-00 KST

- Action: normalized the touched docs toward repo-template structure
- Files touched: `repo-operating-model.md`, `AGENTS.md`, `CLAUDE.md`, local `README.md` guides
- Checks run: `git diff --check`
- Output: merged repo-template writing discipline without losing Markfops-specific constraints
- Blockers: none
- Next: summarize any intentional divergences
```
