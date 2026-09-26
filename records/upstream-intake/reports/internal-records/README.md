# Internal Records

Store the full internal upstream-intake records in this folder.

Recommended naming:

- `UPS-YYYYMMDD-NNN-<scope>.md`

Example:

- `UPS-20260407-001-v1.2.3.md`

## Canonical Example

```md
# UPS-20260409-001-example-release.md

## Review Metadata

- Review id: UPS-20260409-001
- Opened: `2026-04-09 11-00-00 KST`
- Recorded by agent: agent-example-001
- Review date: 2026-04-09
- Reviewer: orchestrator
- Upstream window reviewed: `v2.3.0...v2.4.0`
- Upstream refs or PRs reviewed: `release/v2.4.0`, `PR-1821`
- Downstream branch or working baseline: `main`

## Candidate Change

- Title: Upstream adds structured retry metadata to API error responses
- Upstream area: API transport
- Upstream summary: error responses now include machine-readable retry hints
- Exact upstream feature, provider, contract, or path: `api/errors.ts`, response schema docs
- Exact local downstream surface affected: API gateway adapter and any client code that inspects retryable failures
- Why it matters: this changes how clients and operators can distinguish temporary failures from permanent ones
- What this actually means in practice: downstream can surface better retry behavior without parsing freeform strings
- Before: retry guidance existed only in prose error messages
- After: retry guidance is available in explicit fields
- Concrete consequence: adapters and docs may need small updates
- What is not changing: core error semantics and status codes stay the same
- Expected end-user effect: fewer unnecessary retries and clearer operator debugging
- Breaking or migration risk: low if downstream ignores the new fields, medium if local wrappers reserialize errors
- Relevance to the fork's current stage: useful now because the fork is tightening API contract clarity
- Evidence source category: release notes plus code diff

## Intake Analysis

- What user or operator problem does this change solve upstream? It makes retry behavior easier to automate and reason about.
- What assumptions from upstream do not carry over cleanly to the fork? The fork has wrapper layers that may hide new fields unless updated.
- Is the upstream change about policy, implementation, or both? Mostly implementation with mild contract implications.
- Is this a duplicate or near-duplicate of an existing local change? No direct duplicate, but it overlaps local operator guidance.
- If it overlaps an existing local implementation, whose implementation should win and why? Upstream should win for schema shape; local docs can keep fork-specific guidance.
- What are the main upsides of introducing this change? Better client behavior, clearer docs, less string parsing.
- What are the main downsides, costs, or maintenance burdens? Small adapter updates and regression tests.
- Does this include security or hardening work that collides with, duplicates, or weakens an existing local implementation? No.
- What minute compatibility details matter if this lands? Preserve existing field names exposed by the fork and avoid dropping unknown error metadata in wrappers.
- Literal user or operator scenario: an operator sees a rate-limit failure and the client now waits correctly instead of retrying immediately three times.

## Autonomy Boundary

- Can the agent decide this autonomously?: `yes`
- Why this is safe to decide autonomously, or why it is not: the change improves fidelity without altering product policy
- Existing policy or prior decision that authorizes the choice: upstream bug-fix and compatibility improvements may be adopted when they do not change operator workflow
- What still requires explicit operator judgment, if anything: none

## Escalation

- Escalation required: `no`
- Why operator input is required: n/a
- Recommended decision: `accept`
- What can proceed without approval: adapter update, tests, and docs note
- What is blocked pending approval: nothing
- Re-raise by: n/a

## Decision

- Decision: `accept`
- Decision owner: orchestrator
- Ship target: next sync window
- Related issue, PR, ADR, or note: `DEC-20260409-002`

## Decision Rationale

- Reason for the decision: it improves downstream correctness with low migration risk
- Product or user impact: clients can react to temporary failures more accurately
- Shared-core impact: the adapter should preserve upstream metadata intact
- Fork-specific impact: local wrapper tests need coverage for passthrough fields
- Ecosystem or extension impact: extensions that inspect raw errors may gain useful data
- Docs or migration impact: small note in API compatibility docs
- Overlap with existing local implementation: partial overlap with local operator runbooks, not with code
- Why this decision is better than the obvious alternative: accepting the upstream schema avoids maintaining a local string-parsing workaround
- Compatibility details to preserve during merge: existing wrapper fields and error-code mapping must remain stable

## Acceptance Checks

- Security implications checked: yes
- Correctness or bug-fix value checked: yes
- Maintenance cost checked: yes
- Plugin, extension, or public contract compatibility checked: yes
- Existing local implementation overlap checked: yes
- Upstream-sync clarity checked: yes

## If `accept`

- Merge strategy: take upstream schema changes and patch local wrappers if needed
- Local deviations kept: current operator-facing wording in local docs
- Required tests: response passthrough tests and one client retry scenario
- Follow-up cleanup: remove any local string parsing that becomes redundant

## If `adapt`

- Upstream improvement being preserved: n/a
- Local adaptation approach: n/a
- Why direct adoption is wrong for this fork: n/a
- Compatibility layer or bridge needed: n/a
- Tests that prove the adaptation: n/a
- What local product or policy decision this depends on: n/a

## If `decline`

- Why the fork is declining the change: n/a
- What existing local behavior already covers this area: n/a
- What would need to change for this to be reconsidered: n/a
- Whether this needs a standing note for future reviews: n/a

## Verification

- Verification status: partial, analysis complete and code follow-up pending
- Commands or checks run: release note review, schema diff inspection
- Risk level: low
- Rollback plan if the decision later proves wrong: preserve local wrapper compatibility and drop the new passthrough fields

## Operator Decision Packet

- Decision the operator must make: none
- In simple terms, what this means: n/a
- How this affects architecture or user experience: n/a
- Options: n/a
- Pros of each option: n/a
- Cons of each option: n/a
- Recommended option: n/a
- Consequence of deferring the decision: n/a

## Notes For Next Intake

- Revisit date if needed: 2026-04-23
- Related upstream work to watch: any follow-up changes to error schema documentation
- Follow-up tasks: open implementation ticket for adapter passthrough update
```
