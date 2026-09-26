# Intake Method

This document defines the working method for upstream intake in a downstream fork.

## Candidate Decision Unit

Do not treat a commit as the default review unit.

The default review unit is a candidate decision:

- one upstream change with one practical consequence, or
- several related commits that together require one downstream decision

Use a candidate decision when several commits:

- solve the same problem
- implement one product shift
- land one security hardening theme
- belong to one compatibility-sensitive seam

Split candidate decisions when the grouped change would force different outcomes such as `accept` for one part and `adapt` for another.

## Duplicate-Detection Pass

Before deciding, always ask:

1. Does the fork already have this fix?
2. If yes, is the local fix weaker, stronger, or just differently shaped?
3. Is the local version in shared core or in a fork-only surface?
4. Is the disagreement about implementation, or about product or policy?

If the disagreement is about implementation only, use the collision-resolution policy.
If the disagreement is about policy, escalate first.

## Required Drill-Down: What It Actually Means

Do not restate the upstream note.
Translate it into concrete behavioral consequences.

Required prompts:

- What concrete behavior changes if this lands?
- Who notices first?
- Where does it surface first?
- What problem disappears?
- What new cost, constraint, or maintenance burden appears?
- What will a user or operator literally experience differently?
- If nothing user-visible changes, what architectural or maintenance pressure changes?

### Required Structure

Every important item should be explainable in this shape:

- Exact upstream thing changing:
- Exact local downstream surface affected:
- Before:
- After:
- Concrete consequence:
- What is not changing:

This is the minimum acceptable drill-down form.

### Referent Resolution Rule

Never leave shorthand unresolved.

If the explanation uses phrases like:

- `vendor-specific`
- `some cases`
- `this path`
- `that contract`
- `this behavior`
- `that surface`

replace them with named referents:

- vendor or upstream owner
- provider, product, or feature name
- exact path, config surface, contract, or runtime seam

### Before / After / Consequence

For each major item, answer these explicitly:

- Before: what behavior or assumption existed?
- After: what behavior or assumption exists if this lands?
- Concrete consequence: what changes for users, operators, extension authors, plugin authors, or maintainers?

### Literal Scenario Requirement

For each major item, write at least one literal scenario.

Examples:

- `A user onboarding a provider is now pushed toward API keys instead of being told local subscription reuse is the normal supported path.`
- `A broken safety hook now blocks execution instead of silently allowing the action to continue.`

If you cannot write one literal scenario, the analysis is not deep enough yet.

### Ambiguity Lint

Before finalizing a report item, check for these failure patterns:

- unnamed vendor
- unnamed provider or feature
- unclear `before` state
- unclear `after` state
- missing statement of what is not changing
- vague nouns like `some`, `certain`, `this`, `that`, or `vendor-specific`
- no literal user or operator scenario

Rewrite until those are resolved.

### Exact Change vs Why It Matters

Separate these two questions:

- What exactly changed?
- Why does that change matter to the fork?

Do not blur them into one sentence.

### What Is Not Changing

For each product-shaping or compatibility-sensitive item, state what is not changing.

This prevents false readings like a narrowly scoped upstream removal being misread as abandonment of the whole category.

### Evidence Source Tagging

For each major claim, identify the evidence source category:

- upstream release notes
- upstream PR or commit
- official vendor docs, terms, or pricing page
- local downstream code
- local policy docs

If the claim depends on vendor policy, pricing, legal terms, or product-positioning ambiguity, use internet lookup and prefer official sources.

### Policy vs Implementation Distinction

Always ask:

- Is upstream changing policy, implementation, or both?

Implementation overlap can often be resolved with the collision policy, while policy conflict usually requires escalation first.

## Operator Question Packet

When escalation is needed, package the question like this:

- the decision the operator must make
- what it means in simple terms
- effect on architecture or user experience
- realistic options
- pros of each option
- cons of each option
- recommended option
- what work is blocked until the decision lands

Do not escalate with a vague "please decide" summary.
The packet should name the exact vendor, feature, contract, or path involved.

## Urgency Scoring Rubric

Use this rubric to rank work inside the review.

### Priority 0: Critical

- active or high-confidence security boundary issue
- breaking migration or compatibility failure on a core public contract
- user-facing regression likely to cause data loss, privilege leakage, or severe operational failure

### Priority 1: High

- important security hardening
- breaking or migration-sensitive change with near-term impact
- correctness fix in shared core used broadly by the fork
- change that blocks or strongly shapes upcoming product work

### Priority 2: Medium

- meaningful UX or operator improvement
- maintenance or correctness improvement with limited blast radius
- duplicate or near-duplicate work that still requires a collision decision

### Priority 3: Low

- optional feature additions not relevant to current product direction
- documentation-only or housekeeping changes with no near-term consequence
- changes that can be safely deferred without raising operational risk

## Standard Evidence Ladder

Work from top to bottom until the decision is high confidence.

1. Release note or compare-window summary
2. Underlying PR, commit, or implementation diff
3. Local code surfaces affected
4. Local policy, compatibility, migration, or prior decision docs
5. Verification evidence or tests, if the work is being merged now

Do not stop at step 1 when the decision depends on behavior, compatibility, or policy.

## Standard Merge Recommendation Shapes

Use one of these recommendation shapes in the report:

- `accept as-is`
- `accept with local follow-up`
- `adapt into shared core`
- `adapt into downstream-only surface`
- `decline and carry forward rationale`
- `defer pending operator decision`

These shapes force the report to say not only whether the change is good, but also how it should land.