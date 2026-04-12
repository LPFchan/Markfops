---
name: repo-orchestrator
description: "Route work into the correct artifact layer in a repo that uses repo-template."
argument-hint: "Task, capture item, or maintenance request"
---

# Repo Orchestrator

Use this skill with:

- [../../REPO.md](../../REPO.md)

## What This Skill Produces

- correctly routed repo artifacts
- clear separation between truth, plans, research, decisions, and commit-backed execution
- stable IDs plus lightweight provenance
- operator escalation only when a real judgment call exists

## Procedure

1. Classify the work in routing order.
   - Is this untriaged capture?
   - Is this recurring upstream review?
   - Is this durable truth?
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
   - git commit history via `commit: LOG-*`
   - `upstream-intake/`

3. Assign stable IDs when needed.
   - `IBX-*`
   - `RSH-*`
   - `DEC-*`
   - `LOG-*`
   - `UPS-*`
   - Use the least available `NNN` for file-backed artifact types.
   - For `LOG-*`, derive the suffix from `agent:`, start from the current KST second, and bump forward until unique on the current branch plus default branch.

4. Write the artifact with provenance.
   - For file-backed artifacts, include `Opened: YYYY-MM-DD HH-mm-ss KST` and `Recorded by agent: <agent-id>`.
   - Before drafting, read the destination directory's `README.md` and any explicit template.
   - Match the local guide when it is prescriptive, and stay lightweight when the guide is intentionally minimal.

5. Preserve the separation rules.
   - Do not write speculation straight into `PLANS.md`.
   - Do not let execution records masquerade as decisions.
   - Do not let inbox entries become long-term truth.
   - Do not treat research memos as raw transcripts.

6. If the task crosses layers, create multiple artifacts deliberately.
   - Example: `RSH-*` plus a committed `LOG-*`
   - Example: `DEC-*` plus `PLANS.md`
   - Example: a committed `LOG-*` plus `STATUS.md`
   - Touch multiple layers only when each touched layer has a distinct job.
   - Do not mirror the same evolving thought into every artifact type.

7. If Git commits are created, add commit trailers.
   - `project: <project-id>`
   - `agent: <agent-id>`
   - `role: orchestrator|worker|subagent|operator`
   - `commit: LOG-...[, LOG-...]`
   - `artifacts:` is optional and must not contain `LOG-*`
   - Make the commit message pass the required local validator before retrying.
   - Use the structured body keys `timestamp:`, `changes:`, `rationale:`, and `checks:` with `notes:` optional.

8. If the task is recurring upstream maintenance and the optional module is enabled, use `upstream-intake/` instead of inventing a parallel workflow.

9. If the task is daily inbox pressure review, cluster and triage capture before routing it.
   - Do not summarize every inbox item by default.
   - Promote only survived triage.
   - Leave low-signal ideas in held/discarded counts or clusters instead of expanding them into plans.

## Escalation Triggers

Escalate instead of guessing when the work:

- changes durable product or system truth
- changes public contracts or compatibility posture
- resolves a real policy conflict
- changes operator-facing workflow in a non-obvious way
- overrides a security-sensitive upstream change

## Quality Bar

- clear routing
- sparse promotion
- clear provenance
- clean separation of layers
- reusable artifacts instead of external-tool-only outcomes
