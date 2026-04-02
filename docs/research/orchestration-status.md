# Orchestration Status

## Current Phase

Phase 2: reference repo deep dives

## Revalidation Status

- The new first-class objective `rigorous two-view scroll synchronization` was added after acceptance of `markfops-baseline.md` and `milkdown-deep-dive.md`.
- Those two completed artifacts do not need full re-research from scratch.
- They do require narrow delta revalidation passes focused on scroll-anchor ownership, drift correction, viewport alignment, and synchronization-relevant evidence.
- Cross-reference synthesis should use revalidated versions of those artifacts, not the pre-objective snapshots.

## Active Delta Revalidations

- none

## Phase Scope

- Active scope: no current subagent assignment.
- Next narrow scope: `intend-deep-dive.md` only.
- Out of scope for the next pass: `inkdown` and `SimpleBlockEditor` archaeology, plus any cross-repo synthesis artifacts.
- Orchestrator responsibility: maintain coordination state, launch narrow read-only passes, and reject incomplete evidence.

## Active Assignment

- assigned artifact: none
- assigned agent role: none
- status: awaiting next Phase 2 delegation

## Evidence Standard

- Every accepted finding must cite concrete file paths, symbol names, state ownership, and control-flow evidence.
- Repository summaries, README paraphrases, and folder listings are insufficient.
- Findings must separate observed facts from architectural interpretation.
- Terminology should be normalized so later cross-repo comparisons can map equivalent concepts consistently.
- Markfops constraints remain primary: native feel, markdown fidelity, memory efficiency, incremental migration, viewport morphing quality, rigorous two-view scroll synchronization, and semantic transition quality.

## Next Assignment

- `intend-deep-dive.md`

Delta revalidations are complete. Cross-reference synthesis remains blocked until the remaining repo deep dives exist.

Completed targeted addendum passes:

- `markfops-baseline.md`
- `milkdown-deep-dive.md`

## Blockers

- None currently.

## Latest Completed Artifact

- `milkdown-deep-dive.md`
- completion status: accepted into canonical research state
- key reference finding: Milkdown cleanly separates plugin bootstrapping, parser/serializer boundaries, and command registration, but its canonical state, rendering model, and weak content-derived identity are tightly bound to ProseMirror and browser DOM assumptions.

## Active Reference Context

- Reference target: none
- Comparison anchor: `docs/research/markfops-baseline.md`
- evaluation bias guard: treat each reference repo as a specimen, not a target architecture to transplant.

## Notes for Orchestrator

- Main agent is orchestration-only.
- Use this file to track phase boundaries and the currently active subagent assignment.
- Do not let web-specific implementation details dominate the target architecture just because `milkdown` is more mature.