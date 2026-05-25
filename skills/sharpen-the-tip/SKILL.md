---
name: sharpen-the-tip
description: Iteratively refine an artifact through a structured neutral-subagent review loop until convergence. Trigger on "sharpen", "sharpen the tip", "let's sharpen this", or similar phrasing.
argument-hint: "Goal statement and target artifact (document, plan, spec, prompt, architecture design, etc.)"
---

# Sharpen the Tip

Use this skill when the operator wants to iteratively refine an artifact through a structured subagent review loop until it reaches convergence.

Use it with:

- [../../AGENTS.md](../../AGENTS.md)

This skill runs a neutral-review feedback loop. Every round: a fresh subagent reviews the full artifact, the main agent incorporates findings, and the artifact is rewritten in its entirety. Repeat until both the main agent and a fresh subagent independently find nothing meaningful left.

## What This Skill Produces

- a sharpened artifact, rewritten in full each round until convergence
- a conversation-level delta summary per round (what changed, why, any rejected findings)
- a convergence declaration when the loop terminates

## Core Rule

Every round the artifact must become more internally consistent and more complete. No exception. There is no iteration cap.

## Procedure

### Step 0: Establish Goal and Artifact

**Goal** — what the operator wants to achieve. State it in one sentence. Factual, no priming. This is the lens through which every subagent review operates.

**Artifact** — a complete, self-contained document. For a formal document (file, Obsidian note, RSH): read it in full. For conversation-only: reconstruct from memory and post as v1.

### Step 1: Spawn a Fresh Subagent

Spawn a new subagent every iteration. Never resume. Independence per round is what makes this work. Pass exactly:

1. **Goal** — from Step 0.
2. **Artifact type** — a neutral label (e.g. "This is an implementation plan."). No steering.
3. **Full artifact** — verbatim, unabridged. Never scope to only changed sections.
4. **Source documents** — paths or tool access to referenced documents so the subagent can cross-reference claims.
5. **Prior work** (iteration 2+) — what changed in previous rounds and why, including rejected findings.
6. **Review instructions** — verbatim:

> You are a neutral reviewer. Your job is to critically evaluate the entire artifact below.
>
> Read the whole thing before forming any opinion. If source documents were provided, cross-reference the artifact's claims against them — do not trust characterizations at face value. Your posture is panoramic: look at the forest before the trees. Every section is fair game — do not treat any part as settled or out of scope.
>
> Look for: structural gaps, internal contradictions, missing considerations, unclear or unstated assumptions, logical inconsistencies, scope blind spots, factual errors including misrepresentations of source documents, and anything that would cause this plan to fail or underperform in practice.
>
> Produce a numbered list of findings. For each: state the issue, where it appears, and why it matters. If you find nothing meaningful, say so explicitly with a brief explanation of your reasoning.

### Step 2: Digest Findings

For each finding:

* **Agrees** → incorporate into the rewrite.
* **Disagrees** → alert the user immediately. Silently dropping a finding is never allowed. Tell the user: which finding, why it's rejected, what the user should decide.

Partial agreement is valid. Accept what holds, flag what doesn't.

### Step 3: Rewrite in Full

Rewrite the artifact completely. Not a patch. Not an append. The result must read as a single coherent document.

* Formal document: rewrite in place.
* Conversation artifact: prepare the full rewrite for the next iteration.

### Step 4: Post a Delta Summary

Post a concise summary in the conversation:

* What changed (grouped by theme)
* Why (which finding drove each change)
* Any findings rejected and the reasoning

The conversation thread is the history. No separate changelog, no version files.

### Step 5: Check Convergence

Convergence requires a second, independent opinion:

1. Main agent concludes no meaningful unresolved issues remain.
2. A **fresh subagent** (same source-document access as Step 1; re-inventory after each rewrite) independently finds nothing meaningful.

If either finds something: incorporate (Step 2), rewrite (Step 3), return to Step 1. If both agree: declare convergence:

> "Convergence reached after N iterations. No new meaningful findings from either the main agent or subagent review."

## Escalation Triggers

Escalate to the operator when:

- the loop stalls — oscillating between contradictory findings across 3+ consecutive rounds without forward progress. Present a summary of the deadlock and let the operator break the tie.

## Quality Bar

- every subagent gets the full unabridged artifact, not a scoped view
- every finding is either incorporated or escalated — never silently dropped
- every rewrite is a complete replacement, never a patch
- convergence requires two independent confirmations (main agent + fresh subagent)
- the conversation thread carries the full delta history per round
