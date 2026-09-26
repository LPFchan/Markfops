# Upstream Intake

This directory is a purely optional upstream-review module inside the scaffold. It is opt-in: enable it only when a repo tracks an upstream. Omit the directory entirely otherwise — nothing in the baseline scaffold depends on it.

Use it when a repo:

- is a fork
- tracks an upstream dependency closely
- wants a disciplined recurring review of upstream changes

The system treats upstream review as a decision workflow, not a changelog summary.

## What Lives Here

1. `weekly-upstream-intake-template.md`
   - Full internal decision record template.
2. `operator-weekly-brief-template.md`
   - Shorter operator-facing brief template.
3. `intake-method.md`
   - The drill-down and decision method.
4. `compatibility-watchlist.md`
   - Standing list of compatibility-sensitive surfaces.
5. `known-local-overrides.md`
   - Register of intentional local divergences.
6. `decision-carry-forward.md`
   - Standing decisions to carry into later reviews.
7. `reports/`
   - Storage guidance for internal records and operator briefs.

## Working Model

Each review window should usually produce two artifacts with the same `UPS-*` id:

- one full internal record
- one separate operator brief

The internal record is where exhaustive reasoning lives.
The operator brief is the shorter human-facing translation.

## If You Do Not Need This Module

Remove the directory or leave it dormant.

## If Your Agent Environment Supports Skills

Keep any procedural skill or workflow outside the scaffold and point it back to this directory instead of duplicating its rules.
