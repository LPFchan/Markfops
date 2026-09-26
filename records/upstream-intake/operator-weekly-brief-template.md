# Operator Weekly Brief Template

Use this format for the lighter operator-facing upstream intake summary.

This brief is meant to be fast to scan.
It should summarize conclusions already backed by the fuller record in [weekly-upstream-intake-template.md](weekly-upstream-intake-template.md).
This should be stored as a separate artifact from the full internal record.
The full internal record is where exhaustive reasoning, explicit field coverage, and step-by-step decision logic belong.
The operator brief should translate that material into a shorter, more natural summary rather than mirroring every field name.

## Review Metadata

- Review id:
- Opened: `YYYY-MM-DD HH-mm-ss KST`
- Recorded by agent:
- Review date:
- Upstream window:
- Baseline reviewed against:
- Overall recommendation:

## This Period At A Glance

Write this section as a short, natural summary rather than a checklist.
Use whatever wording fits the week or review window.
It can be 3 to 6 bullets, a short paragraph plus bullets, or a very short freeform summary.
Do not force every category to appear every time.
It is fine to have no security note, two watch items, or no operator decision if that is the real state of the review.
When there are unresolved operator calls, put them near the top of this section.
Autonomous decisions and routine cleanup can sit later.

Try to cover the substance that matters most, when relevant:

- any operator call that is still open
- the one thing worth immediate attention
- anything clearly safe to move ahead on
- any watch item or compatibility concern worth carrying forward
- any security or hardening concern worth surfacing

The phrasing should vary naturally from review to review.
Do not label bullets with rigid stock phrases unless they genuinely read well in that specific brief.

## Decisions Requiring Operator Input

For each item, write a short mini-brief in simple language and avoid internal jargon where possible.
Do not dump the internal-record fields back out as a rigid labeled checklist.
Name the exact vendor, provider, feature, or path involved, but weave it into natural prose.
One short paragraph plus a few optional bullets is usually better than ten labeled bullets.
It is fine to vary the shape from item to item.

Make sure the substance still comes through:

- what decision is actually being asked of the operator
- what exact thing is affected
- what it means in practice
- what is not changing
- what this changes for architecture or user experience
- the real options
- the recommended direction
- what stays blocked until the operator answers

### Item

Short summary paragraph.

Optional bullets if helpful:

- Option A:
  - Pros:
  - Cons:
- Option B:
  - Pros:
  - Cons:
- Option C:
  - Pros:
  - Cons:
- Recommendation:
- Blocked until decided:

Add as many options as the decision actually needs.
Do not force the brief into two options if the real choice set is three or more.

## Watchlist

- Compatibility surfaces to monitor next:
- Decisions to carry forward next review:
- Deferred items and revisit date:

## Decisions Made Autonomously

For each item, keep it short and concrete.
Do not mirror the internal record field-by-field.
Prefer a short paragraph or a few natural bullets that explain what was decided, why it was safe, and what happens next.

### Item

Short summary paragraph.

Optional bullets if helpful:

- Why this was safe to decide:
- Next:
