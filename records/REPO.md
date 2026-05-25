# Repo Operating Model

**Template version: 1.1.3**

This document is the canonical repo contract for repo-template-style repos.

## Core Surfaces

| Surface | Role | Mutability |
| --- | --- | --- |
| `SPEC.md` | Durable statement of what the project is supposed to be. | rewritten |
| `STATUS.md` | What is true right now operationally. | rewritten |
| `PLANS.md` | Accepted future direction, not yet current truth. | rewritten |
| `INBOX.md` | Ephemeral capture waiting for triage. | append then purge |
| `research/` | Curated research memos. | append by new file |
| `decisions/` | Durable decision records with rationale. | append-only by new file |
| `git commit history` | Canonical execution history via `LOG-*`. | append-only by new commit |
| `skills/` | Repeatable procedural workflows for agent tasks. | edit by skill |
| `upstream-intake/` | Optional upstream review subsystem. | append by cadence |

## Agent Compatibility Files

`AGENTS.md` and `CLAUDE.md` are repo-root instruction files. They must stay thin entrypoints into `records/REPO.md`, not competing policy documents.

- `AGENTS.md` is the canonical editable agent-instructions file.
- `CLAUDE.md` is a thin shim pointing to `AGENTS.md`.
- `SKILL.md` defines a bounded reusable procedure under `skills/<name>/`, not repo-wide policy.
- `skills/` ships with adopted repos as repo-native procedural docs, even when the agent runtime does not auto-load skills.

## Artifact Writing Discipline

When writing repo files or commit-backed execution records:

- read the target directory's `README.md` and any explicit template before drafting
- follow the local guide's default shape or canonical example when it defines one
- write normalized repo records, not external transcripts or stream-of-consciousness notes
- separate facts, decisions, open questions, and next steps
- summarize evidence and outcomes; paste raw output only when the output itself is the artifact

Every durable artifact directory must include a `README.md` that defines what belongs there and, when the artifact type benefits from it, a canonical example shape.

## Separation Rules

- `SPEC.md` is not a changelog.
- `STATUS.md` is not a transcript.
- `PLANS.md` is not a brainstorm dump.
- `INBOX.md` is not durable truth.
- `research/` is not raw execution history.
- `decisions/` is not commit-backed execution history.
- Off-Git memory is not a substitute for repo-local canonical docs.

## Roles

### Operator

Final authority for product direction, escalation outcomes, and acceptance of truth changes.

### Orchestrator Agent

Owns synthesis and routing. May triage inbox, run daily IBX reviews, classify work, update `SPEC.md`/`STATUS.md`/`PLANS.md`, create research memos and decision records, create compliant `LOG-*` commits, translate external capture into repo artifacts, and escalate non-obvious calls.

### Worker Agents

Execute bounded tasks. May produce evidence, summaries, and implementation outputs; create compliant `LOG-*` commits when granted commit authority; propose truth changes through the orchestrator.

Must not update `SPEC.md`, `STATUS.md`, or `PLANS.md` directly unless the operator explicitly allows it.

### External Capture Surfaces

Capture and control channels. May create/append inbox capture, request approvals, deliver summaries, surface blocked states.

Must not write truth docs directly.

### Capture Packets

Mutable working envelopes around one or more raw source events. Raw source events are immutable Off-Git.

A capture packet may be appended, edited, split, merged, summarized into `INBOX.md` as an `IBX-*`, or routed into durable repo artifacts after triage. Routed artifacts copy the summary, the stable `IBX-*`, and any needed external provenance handle.

## Inbox Pressure Review

Run daily when the project receives substantial capture. This is focus-protecting triage, not an unconditional digest.

- group related `IBX-*` entries and capture packets into meaningful clusters
- identify stale, duplicate, low-confidence, noisy, or held capture
- classify each cluster: route, research, plan, discard, or leave
- promote only items that survived triage and have an accepted destination
- report counts or clusters of held/discarded/noisy capture; do not summarize every item
- preserve `IBX-*` as permanent provenance even after the inbox line is deleted

Do not update truth docs, research, or decisions directly from raw inbox pressure. Promotion goes through the orchestrator or an operator-approved step.

## Promotion Discipline

Promote sparsely. Each layer receives only the part that belongs there, when it is ready.

| Layer | Receives |
| --- | --- |
| `INBOX.md` | ephemeral routed capture |
| `research/` | reusable exploration, evidence, framing, rejected paths, open questions |
| `decisions/` | meaningful accepted choices and why the winning choice won |
| `PLANS.md` | accepted future work that survived triage |
| `SPEC.md` | concise durable product/system truth after the argument is settled |
| `STATUS.md` | current operational reality |
| `upstream-intake/` | upstream review, conflict, carry-forward, operator escalation |
| git via `LOG-*` | canonical execution history |

A `DEC-*` exists only when a real product, architecture, workflow, trust, upstream, or repo-operating choice has been made. `SPEC.md`, `STATUS.md`, and `PLANS.md` receive concise outcomes, not copied debate.

One task may touch multiple layers, but each layer must receive distinct information.

## Orchestrator Routing Ladder

Classify in this order:

1. Untriaged capture → `INBOX.md`
2. Recurring upstream review → `upstream-intake/`
3. Durable truth → `SPEC.md`
4. Current operational reality → `STATUS.md`
5. Accepted future direction → `PLANS.md`
6. Reusable research → `research/`
7. Meaningful decision → `decisions/`
8. Execution history → `commit: LOG-*`

## Write Rules

- `SPEC.md`, `STATUS.md`, and `PLANS.md` are updated only by the operator or orchestrator.
- `INBOX.md` is a scratch disk. Purge entries once reflected elsewhere or explicitly discarded.
- Daily inbox review reduces pressure; it does not generate a larger digest by default.
- `research/` keeps curated findings only.
- `decisions/` is append-only by new file.
- Execution history lives in git via `LOG-*`. Do not invent a parallel file layer.
- `upstream-intake/` preserves its paired internal-record and operator-brief workflow.
- Truth docs reflect the latest accepted state, not intermediate thoughts.

## Stable IDs

| Prefix | Artifact type | Format |
| --- | --- | --- |
| `IBX-*` | Inbox capture | `IBX-YYYYMMDD-NNN` |
| `RSH-*` | Research | `RSH-YYYYMMDD-NNN` |
| `DEC-*` | Decision | `DEC-YYYYMMDD-NNN` |
| `LOG-*` | Execution record | `LOG-YYYYMMDD-HHMMSS-<agent-suffix>` |
| `UPS-*` | Upstream intake | `UPS-YYYYMMDD-NNN` |

File-backed `NNN` is per day, per artifact type. Claim the next available integer.

File-backed artifacts open with:

- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

`LOG-*` suffix: last up to 6 lowercase alphanumeric chars of `agent:` normalized (lowercased, non-alphanumeric stripped). Claim by starting from current KST second, scanning the current and default branches for duplicate `commit:` values, bumping forward until unique.

## Commit-Backed Execution Records

Required trailers on every commit:

- `project: <project-id>`
- `agent: <agent-id>`
- `role: orchestrator|worker|subagent|operator`
- `commit: LOG-...[, LOG-...]`

Optional: `artifacts: <artifact-id>[, <artifact-id>...]`

Rules:

- `commit:` requires one or more `LOG-*`, comma-separated. First is primary.
- Additional `LOG-*` in `commit:` mean the landed commit absorbs earlier execution records whose separate commits will not remain separate landed history.
- Merge commits mint their own primary `LOG-*`.
- Child `LOG-*` that remain visible as landed history go in `notes:`, not `commit:`.
- `--amend` and `rebase` preserve existing `LOG-*` ids.
- Cherry-pick: keep the same primary `LOG-*` if the original will not also land. Otherwise, the later commit mints a new primary; source `LOG-*` in `notes:` only.
- Pre-land collision: renumber the later branch.
- `artifacts:` must not contain `LOG-*`.

Commit body structure:

```text
<subject line>

timestamp: YYYY-MM-DD HH-mm-ss KST
changes:
- ...
rationale:
- ...
checks:
- ...

project: <project-id>
agent: <agent-id>
role: orchestrator|worker|subagent|operator
commit: LOG-...
artifacts: DEC-..., RSH-...
```

Body rules:

- subject line non-empty
- `timestamp:` required, one line, KST
- `changes:`, `rationale:`, `checks:` required; each must have at least one `- ...` item
- `checks:` may be `- none`
- `notes:` optional

## Commit-Time Enforcement

Enforcement runs locally.

Minimum checks:

- reject normal commits whose primary `LOG-*` was not registered by `scripts/new-commit-message.sh`
- reject commits missing `project:`, `agent:`, `role:`, `commit:`
- reject roles outside `orchestrator|worker|subagent|operator`
- reject malformed `commit:` or `artifacts:` values
- reject `LOG-*` inside `artifacts:`
- reject commits missing required body keys or list items
- reject duplicate `LOG-*` ids on current or default branch
- allow explicit bootstrap or migration exceptions

Required layers:

- `prepare-commit-msg` hook: reject non-generated normal commits
- `commit-msg` hook: validate the contract before commit lands

Every landed commit on the default branch must satisfy the contract regardless of origin (CLI, merge queue, bot, web UI).

## Off-Git Provenance

In-repo provenance records: artifact identity, opened timestamp, recording agent, and commit-level `LOG-*` ids.

Off-Git runtime resolves: which conversation/lineage `agent-id` maps to, which run produced the commit/artifact, top-level vs subagent, which source events produced the artifact, and execution lineage across rebases, cherry-picks, merges, and absorbed `LOG-*` ids.

## Scaffold Rule

`scaffold/` is a ready-to-copy skeleton. Its contents belong at the target repo root after adoption.

- `scaffold/records/` → `records/`
- `scaffold/skills/` → `skills/`
- etc.

### `.gitignore`

Shipped baseline:

- OS noise (`Thumbs.db`, `.DS_Store`)
- commit-generator temp files (`.tmp_commit_msg_*`)

Adopted repos keep the baseline and extend it for their tooling, build artifacts, and environment files.

## Local Divergence

Markfops-specific repo notes:

- `project-id` is `markfops`.
- `docs/` is for Sparkle appcast, release notes publishing, and GitHub Pages assets.
- `ref/` is for reference repositories and local specimens used for research.
- `upstream-intake/` is intentionally omitted until Markfops has a real upstream-review cadence to manage.
