---
name: weekly-upstream-intake
description: "Run recurring upstream intake review inside the repo-template scaffold."
argument-hint: "Upstream release, compare window, or refs to review"
---

# Weekly Upstream Intake

Use this skill with:

- [../../records/upstream-intake/README.md](../../records/upstream-intake/README.md)
- [../../records/upstream-intake/intake-method.md](../../records/upstream-intake/intake-method.md)
- [../../records/upstream-intake/weekly-upstream-intake-template.md](../../records/upstream-intake/weekly-upstream-intake-template.md)
- [../../records/upstream-intake/operator-weekly-brief-template.md](../../records/upstream-intake/operator-weekly-brief-template.md)

Use it when a downstream fork needs a repeatable review of upstream changes.

## What This Skill Produces

- a structured decision record for important upstream changes or grouped change sets
- a separate operator-facing brief that explains what matters and why
- explicit escalation packets for product, compatibility, or policy decisions that cannot be made autonomously

## Procedure

1. Define the upstream scope.
   - Capture the release tag, compare window, or commit range.
   - Record the current downstream branch or baseline.

2. Gather upstream evidence.
   - Start with release notes.
   - Read underlying commits, PRs, docs, or code when the release notes do not explain the practical impact.

3. Group changes into candidate decisions.
   - Combine near-duplicate commits into one decision when they solve the same problem.
   - Separate product-shaping work from routine bug fixes.

4. Analyze each candidate deeply.
   - Follow the drill-down and ambiguity rules in [../../records/upstream-intake/intake-method.md](../../records/upstream-intake/intake-method.md).
   - Make sure each candidate covers the exact upstream and local surfaces, the before and after state, the concrete consequence, what is not changing, overlap or collision with local work, tradeoffs, compatibility details, and at least one literal user or operator scenario.
   - If any of this depends on vendor policy, pricing, legal terms, or external product behavior, use internet lookup and prefer official sources.

5. Decide `accept`, `adapt`, `decline`, or `defer pending operator decision`.
   - Use repo policy, not personal preference.
   - If the change is blocked on product direction, public contract risk, or security-vs-compatibility tradeoffs, escalate.

6. Fill the canonical template.
   - Use [../../records/upstream-intake/weekly-upstream-intake-template.md](../../records/upstream-intake/weekly-upstream-intake-template.md).
   - Use [../../records/upstream-intake/intake-method.md](../../records/upstream-intake/intake-method.md) to keep the analysis and recommendation shape consistent.
   - Write the full record under [../../records/upstream-intake/reports/internal-records/README.md](../../records/upstream-intake/reports/internal-records/README.md).
   - Check the destination directory `README.md` first and mirror its canonical example and level of completeness.

7. Produce the operator brief.
   - Use [../../records/upstream-intake/operator-weekly-brief-template.md](../../records/upstream-intake/operator-weekly-brief-template.md) for the lighter summary.
   - Store it as a separate artifact under [../../records/upstream-intake/reports/operator-briefs/README.md](../../records/upstream-intake/reports/operator-briefs/README.md).
   - Keep the full reasoning in the internal record; the operator brief is the shorter human-facing translation.
   - Check the destination directory `README.md` first so the final artifact reads like a finished brief, not a field dump.

8. If Git commits happen as part of the intake or merge follow-up, include:
   - `project: <project-id>`
   - `agent: <agent-id>`
   - `role: orchestrator|worker|subagent|operator`
   - `commit: LOG-...`
   - optional `artifacts: UPS-..., DEC-...`

## Escalation Triggers

Escalate instead of guessing when the change:

- affects plugin-facing contracts or migration-sensitive compatibility surfaces
- changes onboarding, user workflow, or product positioning
- conflicts with an existing fork-owned implementation and the winning policy is not already explicit
- requires declining or locally overriding a security-relevant upstream change
- removes a compatibility layer or changes a public contract

## Output Quality Bar

- plain-language explanations, not release-note paraphrases
- explicit tradeoffs
- explicit compatibility details
- clear autonomous-vs-operator split
- recommendations grounded in current fork policy and architecture
