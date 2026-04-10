# REPO

This file is the canonical repo contract for Markfops.

This document is the instruction layer for Markfops.

## Purpose

Use this model to keep Markfops legible as a repo managed through durable product docs, research artifacts, decisions, and implementation history.

Markfops is a native macOS Markdown app with an active research and implementation program around a future native WYSIWYG engine. This repo uses a repo-native operating model so that product truth, accepted future direction, reusable research, and execution history do not collapse into external transcripts or one-off notes.

The goals are:

- keep canonical truth in repo-root documents
- keep research reusable and separate from commit-backed execution records
- keep decisions durable and append-only
- make provenance visible through stable artifact ids and commit trailers
- reserve `docs/` for Sparkle and GitHub Pages assets rather than canonical project truth

## Core Surfaces

| Surface | Role | Mutability |
| --- | --- | --- |
| `SPEC.md` | Durable statement of what Markfops is supposed to be. | rewritten |
| `STATUS.md` | Current accepted operational truth. | rewritten |
| `PLANS.md` | Accepted future direction that is not true yet. | rewritten |
| `INBOX.md` | Ephemeral capture waiting for triage. | append then purge |
| `research/` | Curated research memos worth keeping. | append by new file |
| `records/decisions/` | Durable decision records with rationale. | append-only by new file |
| `git commit history` | Canonical execution history through structured commit-backed `LOG-*` records. | append-only by new commit |
| `skills/` | Required procedural workflows for repeatable agent tasks. | edit by skill |
| `upstream-intake/` | Optional upstream review subsystem if Markfops later needs recurring upstream intake. | append by cadence |

Markfops-specific repo notes:

- `docs/` is for Sparkle appcast, release notes publishing, and GitHub Pages assets.
- `ref/` is for reference repositories and local specimens used for research.
- `upstream-intake/` is intentionally omitted until Markfops has a real upstream-review cadence to manage.

## Agent Compatibility Files

Some coding agents look for repo-root instruction files such as `AGENTS.md` or `CLAUDE.md`.

When this repo includes them:

- they act as entrypoints into the canonical rules, not competing policy documents
- they stay short enough that they do not drift from `REPO.md`
- they point writers to the correct canonical surface and local `README.md` guide before drafting
- `skills/<name>/SKILL.md` stays separate because it defines a bounded reusable procedure, not repo-wide policy
- `skills/` ships with Markfops as repo-native procedural documentation, even when the agent runtime does not auto-load skills

Recommended split:

- `REPO.md`
  - canonical rules
- `AGENTS.md`
  - tool-facing summary plus read order
- `CLAUDE.md`
  - Claude-facing shim into the same rules
- `skills/<name>/SKILL.md`
  - procedure for one repeatable workflow

## Artifact Writing Discipline

Macro structure is not enough on its own. Agents should not improvise document shape when the repo already defines one.

When writing repo files or commit-backed execution records:

- read the nearest canonical surface, local directory `README.md`, and any explicit template before drafting
- if the local `README.md` includes a default shape or canonical example, follow it by default
- use the established section order only when the surface actually defines one and it helps the repo stay legible
- write normalized repo records, not external transcripts or stream-of-consciousness notes
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
- `records/decisions/` is not the same as commit-backed execution history.
- `docs/` is not a substitute for the canonical repo operating surfaces.

That separation keeps common questions fast to answer:

- What is the product supposed to be? -> `SPEC.md`
- What is true right now? -> `STATUS.md`
- What future direction is already accepted? -> `PLANS.md`
- What did we learn from exploration? -> `research/`
- What did we decide and why? -> `records/decisions/`
- What actually happened during execution? -> git commit history via `commit: LOG-*`

## Roles

### Operator

The operator is the final authority for product direction, architecture acceptance, workflow changes, and truth updates.

### Orchestrator Agent

The orchestrator owns synthesis and routing.

It may:

- triage inbox items
- run daily inbox pressure reviews
- classify work into the right artifact layer
- update `SPEC.md`, `STATUS.md`, and `PLANS.md`
- create research memos
- create decision records
- create compliant commit-backed execution records
- translate external capture into repo artifacts
- escalate non-obvious product, architecture, workflow, or policy calls

### Worker Agents

Worker agents execute bounded tasks.

They may:

- produce evidence, summaries, and implementation outputs
- create compliant commit-backed execution records when granted commit authority
- propose truth changes through the orchestrator

They should not update `SPEC.md`, `STATUS.md`, or `PLANS.md` directly unless the operator explicitly chooses that flow.

### External Capture Surfaces

External capture surfaces are capture and control channels.

They may:

- create or append inbox capture
- request approvals
- deliver summaries
- surface blocked states

They must not write truth docs directly.

### Capture Packets

Raw external source events are immutable Off-Git events.
Do not treat every raw source event as a separate repo artifact.
Do not treat a full external-tool history as one giant inbox item.

Use capture packets as mutable working envelopes around one or more relevant raw source events.

A capture packet may be:

- appended as new related source events arrive
- edited into a clearer operator-intent summary
- split when it contains multiple independent asks
- merged when several source events are one meaningful thread
- summarized into `INBOX.md` as an `IBX-*`
- routed into durable repo artifacts after triage

Triage should happen per meaningful capture packet.
Routed repo artifacts should copy a short summary, the stable inbox ID, and any needed external provenance handle instead of relying on raw external source staying visible.

## Inbox Pressure Review

`INBOX.md` is an ephemeral scratch disk for untriaged capture.
It is not a backlog, roadmap, brainstorm archive, or project digest.

Run a daily inbox pressure review when the project receives substantial capture.
This review is focus-protecting triage.
It is not an unconditional digest of every random idea.

During the review:

- group related `IBX-*` entries and capture packets into meaningful clusters
- identify stale, duplicate, low-confidence, noisy, or "maybe later" capture
- ask whether each meaningful cluster should route, research, plan, discard, or stay held
- promote only items that survived triage and have an accepted destination
- report counts or clusters of held, discarded, stale, or noisy capture instead of summarizing every low-signal item
- preserve `IBX-*` as a permanent provenance ID even if the inbox line is deleted

Do not update `SPEC.md`, `STATUS.md`, `PLANS.md`, `research/`, or `records/decisions/` directly from raw inbox pressure.
The orchestrator or operator-approved routing step owns promotion.

## Promotion Discipline

Promotion should be sparse.
Do not mirror one evolving thought into every repo surface.

Raw shaping may stay in external capture, generic notes, off-Git capture packets, or `INBOX.md` while the thought is still forming.
Repo artifacts are a refinery: each layer should receive only the part that belongs there, when it is ready.

Use each layer for its distinct job:

- `INBOX.md`
  - ephemeral routed capture
- `research/`
  - reusable exploration, evidence, framing, rejected paths, and open questions
- `records/decisions/`
  - meaningful accepted choices and why the winning choice won
- `PLANS.md`
  - accepted future work that survived triage
- `SPEC.md`
  - concise durable product or system truth after the argument is settled
- `STATUS.md`
  - current operational reality
- `upstream-intake/`
  - upstream review, upstream conflict, carry-forward, and operator escalation for upstream-related choices
- git commit history via `commit: LOG-*`
  - canonical execution history, not truth, decision, plan, or research mirrors

A research memo may remain research forever.
A decision record should exist only when a real product, architecture, workflow, trust, upstream, or repo-operating choice has been made.
`SPEC.md`, `STATUS.md`, and `PLANS.md` should receive concise outcomes, not copied debate.

One task may touch multiple layers, but each touched layer must have its own distinct job.

## Orchestrator Routing Ladder

When new work arrives, the orchestrator should classify it in this order:

1. Is this untriaged capture?
   - Route to `INBOX.md`.
2. Is this recurring upstream review?
   - Route to `upstream-intake/`.
3. Is this durable truth about what the project is?
   - Route to `SPEC.md`.
4. Is this current operational reality?
   - Route to `STATUS.md`.
5. Is this accepted future direction?
   - Route to `PLANS.md`.
6. Is this reusable exploration or horizon-expansion work?
   - Route to `research/`.
7. Is this a meaningful decision with rationale?
   - Route to `records/decisions/`.
8. Is this implementation or execution that should land in git history?
   - Route to a compliant commit-backed `LOG-*` record.

One task may legitimately touch multiple layers. For example:

- a research session can create `RSH-*` plus a committed `LOG-*`
- a product choice can create `DEC-*` and update `PLANS.md`
- implementation progress can create a committed `LOG-*` and update `STATUS.md`

Touch multiple layers only when each touched layer has a distinct job.
Do not copy the same evolving thought into research, decision, plan, spec, status, upstream, and execution surfaces.

## Write Rules

- `SPEC.md`, `STATUS.md`, and `PLANS.md` should be updated only by the operator or orchestrator.
- `INBOX.md` is an aggressive scratch disk. Purge entries once they are reflected elsewhere or explicitly discarded.
- Daily inbox review should reduce pressure by clustering, routing, holding, or purging capture; it should not generate a larger digest by default.
- `research/` keeps curated findings only.
- `records/decisions/` is append-only by new decision file.
- Routine execution history lives in git commit history through commit-backed `LOG-*` records.
- Do not invent a parallel execution-history file layer.
- If work produces no durable repo change, route only the durable outcome that belongs elsewhere or keep the raw trace Off-Git.
- `upstream-intake/` should preserve its own paired internal-record and operator-brief workflow.
- Truth docs should reflect the latest accepted state, not every intermediate thought.

## Stable IDs

This model assumes:

- `project-id` identifies the repo or workspace
- `agent-id` identifies the conversation or actor lineage that originated the artifact or commit
- subagents receive their own `agent-id`
- Off-Git systems resolve runs, child lineage, messages, events, and commit history from `agent-id`

Recommended prefixes:

- `IBX-YYYYMMDD-NNN`
- `RSH-YYYYMMDD-NNN`
- `DEC-YYYYMMDD-NNN`
- `LOG-YYYYMMDD-HHMMSS-<agent-suffix>`
- `UPS-YYYYMMDD-NNN`

File-backed artifact numbering is per day and per artifact type. Any agent may claim the next file-backed `NNN` by checking the least available value.

File-backed stable-ID-bearing artifacts should open with:

- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

Commit-backed `LOG-*` ids use this format:

- `LOG-YYYYMMDD-HHMMSS-<agent-suffix>`
- `<agent-suffix>` is the last up to 6 lowercase alphanumeric characters of the normalized `agent:` value
- normalize `agent:` by lowercasing it and removing non-alphanumeric characters

When claiming a new `LOG-*` id:

- start from the current KST timestamp plus the derived agent suffix
- scan the current branch and the default branch for existing `commit:` values
- if the candidate id already exists, bump the timestamp forward by one second until it is unique

## Commit-Backed Execution Records

After a repo adopts this system, every commit should include these trailers:

- `project: <project-id>`
- `agent: <agent-id>`
- `role: orchestrator|worker|subagent|operator`
- `commit: LOG-...[, LOG-...]`

Optional trailer:

- `artifacts: <artifact-id>[, <artifact-id>...]`

Rules:

- `commit:` must include one or more `LOG-*` ids, comma-separated.
- The first `LOG-*` in `commit:` is the commit's primary execution id.
- Additional `LOG-*` ids mean the landed commit canonically absorbs earlier execution records whose separate commits will not remain separate landed history.
- Every merge commit must mint its own primary `LOG-*`.
- When child commits remain visible as landed history, mention child `LOG-*` ids in `notes:` instead of reusing them in `commit:`.
- `--amend` and `rebase` should preserve existing `LOG-*` ids.
- If cherry-pick relocates work and the original commit will not also land, keep the same primary `LOG-*`.
- If both original and cherry-picked commits could land, the later commit must mint a new primary `LOG-*`; source `LOG-*` ids may be mentioned only in `notes:`.
- If a collision is discovered before landing, the later branch renumbers before merge.
- `artifacts:` is optional.
- `artifacts:` may list more than one stable ID, comma-separated.
- `artifacts:` must not include any `LOG-*`.
- The commit side and the repo-artifact side should reinforce the same provenance graph.

Commit bodies must use this lowercase structure:

```text
<subject line>

timestamp: YYYY-MM-DD HH-mm-ss KST
changes:
- ...
rationale:
- ...
checks:
- ...
notes:
- ...

project: <project-id>
agent: <agent-id>
role: orchestrator|worker|subagent|operator
commit: LOG-...
artifacts: DEC-..., RSH-...
```

Body rules:

- the subject line must be non-empty
- `timestamp:` is required and must be one line in KST
- `changes:`, `rationale:`, and `checks:` are required
- each required section must contain at least one `- ...` item
- `checks:` may be `- none`
- `notes:` is optional

## Commit-Time Enforcement

If the repo enables commit hooks, every attempted commit should be checked against these provenance rules.

Recommended minimum enforcement:

- reject commits that do not include `project:`, `agent:`, `role:`, and `commit:`
- reject roles outside `orchestrator|worker|subagent|operator`
- reject malformed `commit:` values
- reject malformed or empty `artifacts:` values when present
- reject any `artifacts:` value that includes `LOG-*`
- reject commits that do not include the required body keys and list items
- reject duplicate `LOG-*` ids on the current branch or default branch
- allow explicit bootstrap or migration exceptions

The goal is not perfect policy automation. The goal is to stop obviously non-compliant commits before they land.

Best practice is to use both:

- local git hooks for fast feedback before the commit is created
- CI for remote re-validation on push or pull request

Every landed commit on the default branch must satisfy the same contract regardless of whether it came from the CLI, a merge queue, a bot, or a web UI.
If a landing path cannot produce compliant commit messages, the repo should not use that landing path.

## Off-Git Provenance

Repo artifacts stay lightweight on purpose.

In-repo provenance answers:

- what file-backed artifact this is
- when it was opened
- which agent recorded it
- which `LOG-*` execution ids belong to each commit

The Off-Git runtime should answer:

- which conversation or actor lineage the `agent-id` maps to
- which exact run inside that lineage produced the commit or artifact
- whether the agent was top-level or a subagent
- which source events produced the artifact
- how execution lineage maps across rebases, cherry-picks, merges, and absorbed `LOG-*` ids

## Markfops Notes

- `docs/` is for Sparkle appcast, release notes publishing, and GitHub Pages assets.
- `ref/` is for reference repositories and local specimens used for research.
- `upstream-intake/` is intentionally omitted until Markfops has a real upstream-review cadence to manage.

Keep skills lightweight and procedural. They should point back to this operating model rather than duplicating all of its rules.
