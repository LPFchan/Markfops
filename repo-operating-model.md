# Repo Operating Model

This document is the instruction layer for Markfops.

## Purpose

Use this model to keep Markfops legible as a repo managed through durable product docs, research artifacts, decisions, and implementation history.

Markfops is a native macOS Markdown app with an active research and implementation program around a future native WYSIWYG engine. This repo uses a repo-native operating model so that product truth, accepted future direction, reusable research, and execution history do not collapse into chat transcripts or one-off notes.

The goals are:

- keep canonical truth in repo-root documents
- keep research reusable and separate from raw worklogs
- keep decisions durable and append-only
- make provenance visible through stable artifact ids and commit trailers
- reserve `docs/` for Sparkle and GitHub Pages assets rather than canonical project truth

## Core Surfaces

| Surface | Role | Mutability |
| --- | --- | --- |
| `SPEC.md` | Durable statement of what Markfops is supposed to be. | rewritten |
| `STATUS.md` | Current accepted operational truth. | rewritten |
| `PLANS.md` | Accepted future direction that is not true yet. | rewritten |
| `INBOX.md` | Untriaged intake waiting for routing. | append then purge |
| `research/` | Curated research memos worth keeping. | append by new file |
| `records/decisions/` | Durable decision records with rationale. | append-only by new file |
| `records/agent-worklogs/` | Execution history for agent runs and workstreams. | append-only |
| `upstream-intake/` | Optional upstream review subsystem if Markfops later needs recurring upstream intake. | append by cadence |

Markfops-specific repo notes:

- `docs/` is for Sparkle appcast, release notes publishing, and GitHub Pages assets.
- `ref/` is for reference repositories and local specimens used for research.
- `upstream-intake/` is intentionally omitted until Markfops has a real upstream-review cadence to manage.

## Agent Compatibility Files

Some coding agents look for repo-root instruction files such as `AGENTS.md` or `CLAUDE.md`.

When this repo includes them:

- they act as entrypoints into the canonical rules, not competing policy documents
- they stay short enough that they do not drift from `repo-operating-model.md`
- they point writers to the correct canonical surface and local `README.md` guide before drafting
- `skills/<name>/SKILL.md` stays separate because it defines a bounded reusable procedure, not repo-wide policy

Recommended split:

- `repo-operating-model.md`
  - canonical rules
- `AGENTS.md`
  - tool-facing summary plus read order
- `CLAUDE.md`
  - Claude-facing shim into the same rules
- `skills/<name>/SKILL.md`
  - procedure for one repeatable workflow

## Artifact Writing Discipline

Macro structure is not enough on its own. Agents should not improvise document shape when the repo already defines one.

When writing repo artifacts:

- read the nearest canonical surface, local directory `README.md`, and any explicit template before drafting
- if the local `README.md` includes a default shape or canonical example, follow it by default
- default to the established section order for that artifact type unless the task has a strong reason to differ
- write normalized repo records, not chat transcripts or stream-of-consciousness notes
- keep facts, decisions, open questions, and next steps clearly separated
- summarize evidence and outcomes instead of pasting raw command output unless the literal output is the artifact
- prefer short declarative bullets or paragraphs over filler

## Separation Rules

These boundaries are mandatory:

- `SPEC.md` is not a changelog.
- `STATUS.md` is not a transcript.
- `PLANS.md` is not a brainstorm dump.
- `INBOX.md` is not durable truth.
- `research/` is not raw execution history.
- `records/decisions/` is not the same as `records/agent-worklogs/`.
- `docs/` is not a substitute for the canonical repo operating surfaces.

That separation keeps common questions fast to answer:

- What is the product supposed to be? -> `SPEC.md`
- What is true right now? -> `STATUS.md`
- What future direction is already accepted? -> `PLANS.md`
- What did we learn from exploration? -> `research/`
- What did we decide and why? -> `records/decisions/`
- What happened during execution? -> `records/agent-worklogs/`

## Roles

### Operator

The operator is the final authority for product direction, architecture acceptance, workflow changes, and truth updates.

### Orchestrator Agent

The orchestrator owns synthesis and routing. It may:

- triage `INBOX.md`
- update `SPEC.md`, `STATUS.md`, and `PLANS.md`
- create `RSH-*`, `DEC-*`, and `LOG-*` artifacts
- translate messenger intake into canonical repo artifacts
- escalate non-obvious product, architecture, workflow, or policy calls

### Worker Agents

Worker agents execute bounded tasks. They may:

- append to worklogs
- produce implementation outputs and evidence
- propose truth changes through the orchestrator

They should not update `SPEC.md`, `STATUS.md`, or `PLANS.md` directly unless the operator explicitly chooses that flow.

### Messenger Surfaces

Messenger surfaces are intake and control channels.

They may:

- create or append inbox intake
- request approvals
- deliver summaries
- surface blocked states

They must not write truth docs directly.

## Orchestrator Routing Ladder

When new work arrives, classify it in this order:

1. Is this untriaged intake? Route it to `INBOX.md`.
2. Is this recurring upstream review? Route it to `upstream-intake/` if that subsystem exists.
3. Is this durable truth about the product? Route it to `SPEC.md`.
4. Is this current operational reality? Route it to `STATUS.md`.
5. Is this accepted future direction? Route it to `PLANS.md`.
6. Is this reusable exploration or horizon-expansion work? Route it to `research/`.
7. Is this a meaningful decision with rationale? Route it to `records/decisions/`.
8. Is this execution history? Route it to `records/agent-worklogs/`.

One task may legitimately touch multiple layers. Examples:

- `RSH-*` plus `LOG-*`
- `DEC-*` plus `PLANS.md`
- `LOG-*` plus `STATUS.md`

## Write Rules

- Update `SPEC.md`, `STATUS.md`, and `PLANS.md` only when accepted truth changes.
- Purge `INBOX.md` items after they are reflected elsewhere.
- Keep research memos focused on reusable findings, not chat residue.
- Create a new `DEC-*` when a decision changes rather than rewriting the old one into historylessness.
- Append to worklogs instead of editing away prior execution facts unless a migration note is required.
- If `upstream-intake/` is later introduced, preserve its paired internal-record and operator-brief workflow instead of inventing a parallel format.
- Preserve `ref/` as research input, not canonical project truth.

## Stable IDs

Markfops uses these artifact prefixes:

- `IBX-*` for intake
- `RSH-*` for research
- `DEC-*` for decisions
- `LOG-*` for worklogs

The project id is fixed to `markfops`.

This model assumes:

- `project-id` identifies the repo or workspace
- `agent-id` identifies one conversation or run, 1:1
- subagents receive their own `agent-id`

Numbering is per day and per artifact type using the least available `NNN`.

Every stable-ID-bearing artifact should include:

- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

Migrated artifacts may also note the original path when that helps preserve continuity.

## Commit Provenance

After the repo-template migration commit lands, every normal commit must include these trailers:

- `project: markfops`
- `agent: <agent-id>`
- `role: orchestrator|worker|subagent|operator`
- `artifacts: <artifact-id>[, <artifact-id>...]`

Rules:

- `artifacts:` may list more than one stable ID.
- A normal commit should always reference at least one artifact.
- Bootstrap or migration exceptions are allowed only when the exception is explicit in the commit message.
- The repo-local artifact graph and commit history should reinforce one another.

Use `.gitmessage.markfops` as the local commit template helper, `.githooks/commit-msg` plus `scripts/install-hooks.sh` for local enforcement, and `scripts/check-commit-standards.sh` plus `scripts/check-commit-range.sh` for local or CI validation.

## Commit-Time Enforcement

If commit hooks or CI checks are enabled, every attempted or pushed commit should be checked against these provenance rules.

Recommended minimum enforcement:

- reject commits that do not include `project:`, `agent:`, `role:`, and `artifacts:`
- reject `project:` values other than `markfops`
- reject roles outside `orchestrator|worker|subagent|operator`
- reject empty or malformed artifact ID lists
- allow only explicit bootstrap or migration exceptions

The goal is not perfect policy automation. The goal is to stop obviously non-compliant commits before they land.

## Off-Git Provenance

Repo artifacts stay lightweight on purpose.

In-repo provenance answers:

- what artifact this is
- when it was opened
- which agent wrote the record

Off-repo or runtime context may answer:

- which conversation or run the `agent-id` maps to
- whether the agent was top-level or a subagent
- which messages or events produced the artifact
- which commits belong to that `agent-id`

## Skills

`skills/` contains Markfops-local procedural skills. Keep them lightweight and procedural. They should point back to this operating model rather than duplicating all of its rules.
