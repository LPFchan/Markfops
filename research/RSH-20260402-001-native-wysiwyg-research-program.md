# RSH-20260402-001: Native WYSIWYG Research Program
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: native-wysiwyg-research-plan.md

Status: migrated bootstrap memo

Related artifacts: `SPEC.md`, `PLANS.md`, `STATUS.md`, `LOG-20260409-001`

## Purpose

This memo preserves the project-native research charter from the retired `native-wysiwyg-research-plan.md`. It is not the old orchestration script, subagent prompt library, or control plane. It is the durable statement of what that research program was trying to learn and the quality bar it established.

## Main Question

What is the smallest native architecture that lets Markfops evolve toward a WYSIWYG Markdown engine without giving up Markdown-first persistence, native macOS editing quality, or trustworthy dual-view behavior?

## Objective

Build a native AppKit-based WYSIWYG Markdown engine path for Markfops that:

- keeps Markdown as the canonical document format
- feels like a native macOS text system component rather than a web app embedded in a shell
- remains lightweight in memory and responsive for long documents
- can move progressively from inline rich Markdown editing toward more Notion-like block behavior
- morphs visible text objects between editor and preview presentations at 60 fps, with 120 fps as a stretch target
- keeps editor and preview scroll position rigorously synchronized through stable anchors and correction, not only matched percentages
- models semantic Markdown transitions such as heading, quote, inline-code, code-block, list, emphasis, link, and table presentation
- avoids the preview-to-source corruption class of bugs by design

## Reference Corpus

- Current Markfops codebase: `Markfops/App`, `Markfops/State`, `Markfops/Editor`, `Markfops/Renderer`, `Markfops/Parsing`, `Markfops/Views`, and `Markfops/Commands`
- Reference specimens: `ref/milkdown`, `ref/intend`, `ref/inkdown`, and `ref/SimpleBlockEditor`
- Expected use: learn architecture, tradeoffs, failure modes, and implementation patterns; do not adopt any specimen as a production dependency

## Core Principles

- Markdown must remain the canonical persisted format.
- Markfops should remain native macOS-first rather than adopting a browser-core editor architecture.
- Reference repositories are specimens for transferability analysis, not direct dependencies or transplant candidates.
- Stable semantic identity, rigorous editor/preview synchronization, and semantic transition quality are first-class requirements for the future engine.
- Parsing, semantic model, rendering, interaction, motion, synchronization, and persistence should stay separable and testable.
- Smooth transitions should come from shared object identity and measured geometry, not screenshot cross-fades.
- Offscreen work can be lazy; visible-region interaction and motion define the frame-budget-critical path.

## Methodology

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

## Quality Bar

Research outputs should make it possible to answer concrete engineering questions without restarting archaeology:

- which type owns the canonical model
- which function applies rendering, parsing, source mapping, scroll mapping, selection mapping, or serialization
- where state variables gate expensive work
- where block identity is created, reused, transformed, or lost
- where preview, editor, parser, renderer, command, or serializer boundaries can corrupt source fidelity
- where frame time, layout churn, invalidation breadth, or cross-presentation drift could break viewport transitions

## Routing After Migration

- Put product truth in `SPEC.md`.
- Put accepted future direction in `PLANS.md`.
- Put current reality in `STATUS.md`.
- Keep future research findings in `research/` as `RSH-*` memos.
- Record durable decisions in `records/decisions/`.
- Record execution history and handoffs in `records/agent-worklogs/`.
- Treat old copy-paste subagent prompts and orchestration-status prose as retired execution scaffolding, not research findings.
