---
name: daily-inbox-pressure-review
description: "Run a focus-protecting daily review of INBOX.md and external capture packets."
argument-hint: "Date, inbox range, capture packet, external source, or triage focus"
---

# Daily Inbox Pressure Review

Use this skill with:

- [../../REPO.md](../../REPO.md)
- [../../INBOX.md](../../INBOX.md)

Use it when the operator or orchestrator wants a daily IBX review.

## What This Skill Produces

- reduced inbox pressure
- grouped capture clusters
- explicit route/research/plan/discard/leave recommendations
- promotion of survived triage only
- optional concise operator questions when routing is blocked

It should not produce a giant digest of every captured idea.

## Procedure

1. Gather active capture.
   - Read `INBOX.md`.
   - Include relevant external capture packets when available.
   - Treat raw external source events as immutable Off-Git events, not as repo artifacts.

2. Build meaningful capture packets.
   - Group related raw source events and `IBX-*` entries.
   - Split unrelated ideas that were captured together.
   - Merge near-duplicates.
   - Keep stable `IBX-*` provenance when an inbox line is later deleted.

3. Protect focus.
   - Identify stale, duplicate, low-confidence, noisy, or "maybe later" clusters.
   - Report noisy/held/discarded capture by count or cluster when details would be distracting.
   - Do not create a "100 future directions" summary.

4. Triage each meaningful cluster.
   - `route` when it has an accepted destination now.
   - `research` when a reusable question is worth investigating.
   - `plan` only when future direction is accepted.
   - `discard` when it is stale, duplicate, irrelevant, or intentionally dropped.
   - `leave` when the operator wants the pressure valve to hold it a little longer.

5. Promote only survived triage.
   - Do not update `SPEC.md`, `STATUS.md`, `PLANS.md`, `research/`, or `records/decisions/` directly from raw inbox.
   - Route through the orchestrator or operator-approved decision.
   - Copy short summaries and provenance IDs into routed artifacts.
   - Do not rely on raw external source staying visible.

6. Clean the inbox.
   - Purge entries reflected elsewhere.
   - Purge entries explicitly discarded.
   - Keep or rewrite held entries only when they still reduce pressure.
   - Leave a compact pressure summary if helpful, then clear daily scratch notes after routing.

## Quality Bar

- focus-protecting
- concise clusters instead of exhaustive digest
- preserved provenance
- clear route/research/plan/discard/leave outcomes
- no direct truth-doc updates from raw inbox pressure
