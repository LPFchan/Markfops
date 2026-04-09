---
name: repo-orchestrator
description: "Route Markfops work into the correct repo artifact layer."
argument-hint: "Task, capture item, or maintenance request"
---

# Repo Orchestrator

Use this skill with:

- [`REPO.md`](../../REPO.md)
- [`SPEC.md`](../../SPEC.md)
- [`STATUS.md`](../../STATUS.md)
- [`PLANS.md`](../../PLANS.md)
- [`INBOX.md`](../../INBOX.md)

## What This Skill Produces

- correctly routed Markfops repo artifacts
- clear separation between truth, plans, research, decisions, and execution history
- stable IDs with lightweight provenance
- escalation only when a real product, architecture, or workflow judgment call exists

## Procedure

1. Classify the work in routing order.
   - Is this untriaged capture?
   - Is this recurring upstream review?
   - Is this durable product truth?
   - Is this current operational reality?
   - Is this accepted future direction?
   - Is this reusable research?
   - Is this a durable decision?
   - Is this execution history?

2. Route it to the correct artifact layer.
   - `SPEC.md`
   - `STATUS.md`
   - `PLANS.md`
   - `INBOX.md`
   - `research/`
   - `records/decisions/`
   - `records/agent-worklogs/`

3. Assign stable IDs when needed.
   - `IBX-*`
   - `RSH-*`
   - `DEC-*`
   - `LOG-*`
   - Use the least available `NNN` for that date and artifact type.
   - Prefer reusing the current relevant `LOG-*` before claiming a new one.

4. Write the artifact with provenance.
   - Include `Opened: YYYY-MM-DD HH-mm-ss KST`
   - Include `Recorded by agent: <agent-id>`
   - Before drafting, read the destination directory's `README.md` and any explicit template.
   - Match the local guide when it is prescriptive, and stay lightweight when the guide is intentionally minimal.

5. Preserve the separation rules.
   - Do not write speculation straight into `PLANS.md`.
   - Do not let worklogs masquerade as decisions.
   - Do not let inbox entries become long-term truth.
   - Do not treat research memos as raw transcripts.

6. If the task crosses layers, create multiple artifacts deliberately.
   - Example: `RSH-*` plus `LOG-*`
   - Example: `DEC-*` plus `PLANS.md`
   - Example: `LOG-*` plus `STATUS.md`
   - Touch multiple layers only when each touched layer has a distinct job.
   - Do not mirror the same evolving thought into every artifact type.

7. If Git commits are created, add commit trailers.
   - `project: markfops`
   - `agent: <agent-id>`
   - `role: orchestrator|worker|subagent|operator`
   - `artifacts: <artifact-id>[, <artifact-id>...]`
   - Prefer referencing and updating an existing relevant `LOG-*` before creating a new one.

8. If the task is recurring upstream maintenance and the optional module is enabled, use `upstream-intake/` instead of inventing a parallel workflow.

9. If the task is daily inbox pressure review, cluster and triage capture before routing it.
   - Do not summarize every inbox item by default.
   - Promote only survived triage.
   - Leave low-signal ideas in held/discarded counts or clusters instead of expanding them into plans.

## Escalation Triggers

Escalate instead of guessing when the work:

- changes durable product truth
- changes public contracts or compatibility posture
- changes accepted architecture direction
- changes repo workflow in a non-obvious way
- requires declining a higher-risk implementation shortcut

## Quality Bar

- clear routing
- sparse promotion
- clear provenance
- clean separation of layers
- reusable artifacts instead of external-tool-only outcomes
