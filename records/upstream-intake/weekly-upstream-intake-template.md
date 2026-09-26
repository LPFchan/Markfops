# Weekly Upstream Intake Template

Use this template during a periodic upstream intake review.
Use the same template when a review item must be escalated for a critical decision.

## Review Metadata

- Review id:
- Opened: `YYYY-MM-DD HH-mm-ss KST`
- Recorded by agent:
- Review date:
- Reviewer:
- Upstream window reviewed:
- Upstream refs or PRs reviewed:
- Downstream branch or working baseline:

## Candidate Change

- Title:
- Upstream area:
- Upstream summary:
- Exact upstream feature, provider, contract, or path:
- Exact local downstream surface affected:
- Why it matters:
- What this actually means in practice:
- Before:
- After:
- Concrete consequence:
- What is not changing:
- Expected end-user effect:
- Breaking or migration risk:
- Relevance to the fork's current stage:
- Evidence source category:

## Intake Analysis

- What user or operator problem does this change solve upstream?
- What assumptions from upstream do not carry over cleanly to the fork?
- Is the upstream change about policy, implementation, or both?
- Is this a duplicate or near-duplicate of an existing local change?
- If it overlaps an existing local implementation, whose implementation should win and why?
- What are the main upsides of introducing this change?
- What are the main downsides, costs, or maintenance burdens?
- Does this include security or hardening work that collides with, duplicates, or weakens an existing local implementation?
- What minute compatibility details matter if this lands?
- Literal user or operator scenario:

## Autonomy Boundary

- Can the agent decide this autonomously?: `yes` | `no`
- Why this is safe to decide autonomously, or why it is not:
- Existing policy or prior decision that authorizes the choice:
- What still requires explicit operator judgment, if anything:

## Escalation

- Escalation required: `yes` | `no`
- Why operator input is required:
- Recommended decision: `accept` | `adapt` | `decline` | `defer`
- What can proceed without approval:
- What is blocked pending approval:
- Re-raise by:

## Decision

- Decision: `accept` | `adapt` | `decline`
- Decision owner:
- Ship target:
- Related issue, PR, ADR, or note:

## Decision Rationale

- Reason for the decision:
- Product or user impact:
- Shared-core impact:
- Fork-specific impact:
- Ecosystem or extension impact:
- Docs or migration impact:
- Overlap with existing local implementation:
- Why this decision is better than the obvious alternative:
- Compatibility details to preserve during merge:

## Acceptance Checks

Complete this section for every decision type.

- Security implications checked:
- Correctness or bug-fix value checked:
- Maintenance cost checked:
- Plugin, extension, or public contract compatibility checked:
- Existing local implementation overlap checked:
- Upstream-sync clarity checked:

## If `accept`

- Merge strategy:
- Local deviations kept:
- Required tests:
- Follow-up cleanup:

## If `adapt`

- Upstream improvement being preserved:
- Local adaptation approach:
- Why direct adoption is wrong for this fork:
- Compatibility layer or bridge needed:
- Tests that prove the adaptation:
- What local product or policy decision this depends on:

## If `decline`

- Why the fork is declining the change:
- What existing local behavior already covers this area:
- What would need to change for this to be reconsidered:
- Whether this needs a standing note for future reviews:

## Verification

- Verification status:
- Commands or checks run:
- Risk level:
- Rollback plan if the decision later proves wrong:

## Operator Decision Packet

Complete this section only when operator input is required.

- Decision the operator must make:
- In simple terms, what this means:
- How this affects architecture or user experience:
- Options:
- Pros of each option:
- Cons of each option:
- Recommended option:
- Consequence of deferring the decision:

## Notes For Next Intake

- Revisit date if needed:
- Related upstream work to watch:
- Follow-up tasks:
