# RSH-20260402-001: Native WYSIWYG Research Program
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: native-wysiwyg-research-plan.md

## Metadata

- Status: migrated bootstrap memo
- Scope: research program charter and methodology
- Related artifacts: `SPEC.md`, `PLANS.md`, `STATUS.md`, `LOG-20260409-001`

## Research Question

What is the smallest native architecture that lets Markfops evolve toward a WYSIWYG Markdown engine without giving up Markdown-first persistence, native macOS editing quality, or trustworthy dual-view behavior?

## Why This Belongs To Markfops

The repo already contains a working native Markdown editor plus a substantial reference corpus under `ref/`. The research program exists to turn that foundation into an implementation path rather than a generic editor brainstorm.

## Durable Findings Preserved From The Original Plan

- Markdown must remain the canonical persisted format.
- Markfops should remain native macOS-first rather than adopting a browser-core editor architecture.
- Reference repositories are specimens for transferability analysis, not direct dependencies or transplant candidates.
- Stable semantic identity, rigorous editor/preview synchronization, and semantic transition quality are first-class requirements for the future engine.
- The current repo needs durable artifacts for research, decisions, and execution history instead of a chat-only control plane.

## Methodology Worth Preserving

### Code Archaeology Before Abstraction

Read implementation files directly and cite concrete file paths, symbols, state ownership, and control flow before writing architectural conclusions.

### Separate Fact From Interpretation

Every meaningful research memo should distinguish observed behavior from proposed synthesis so future readers can re-evaluate assumptions without rereading the entire codebase.

### Transferability Over Admiration

For each outside specimen, classify ideas into:

- copy nearly verbatim
- generalize the idea
- avoid

This prevents demos, polish, or maturity from overpowering architectural fit.

### Markfops Constraints Win

When tradeoffs appear, prefer:

- Markdown fidelity over tree-first convenience
- native editing quality over web portability
- explicit synchronization ownership over renderer-local hacks
- visible-region incremental work over whole-document replacement

## Recommended Routing

- Put product truth in `SPEC.md`.
- Put accepted future direction in `PLANS.md`.
- Put current reality in `STATUS.md`.
- Keep future research findings in `research/` as `RSH-*` memos.
- Record durable decisions in `records/decisions/`.
- Record execution history and handoffs in `records/agent-worklogs/`.
