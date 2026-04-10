# Decisions

This directory stores durable decision records for Markfops.

## Naming

Create one file per meaningful decision:

- `DEC-YYYYMMDD-NNN-short-title.md`

## Decision Hygiene

- Decision records are append-only by new file.
- If a decision changes later, create a new `DEC-*` that supersedes the old one.
- Do not fold raw execution history into a decision record.

## Required Opening

Each decision file should begin with:

- `# DEC-YYYYMMDD-NNN: <Short Decision Title>`
- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

## Default Shape

- Metadata
- Decision
- Context
- Options considered
- Rationale
- Consequences

Use that section order by default unless the decision genuinely needs a different structure.

## Canonical Example

```md
# DEC-20260409-001: Keep Repo-Template Shape Guides In Local READMEs

Opened: 2026-04-09 09-45-00 KST
Recorded by agent: agent-example-001

## Metadata

- Status: accepted
- Deciders: operator, orchestrator
- Related ids: RSH-20260409-001, LOG-20260410-230133-logmig

## Decision

Use the local surface guides and directory `README.md` files as the formatting contract for Markfops repo artifacts.

## Context

Markfops already adopted repo-template, but some documents were created with lighter local formatting that left too much freedom in section order and artifact shape.

## Options Considered

- Keep only macro-level surface guidance
- Add local guide sections with default shapes and examples
- Let each agent improvise the artifact shape case by case

## Rationale

One strong local guide per artifact type makes the repo easier to extend without creating a second policy layer or requiring agents to infer house style from old files.

## Consequences

- New decision records should follow the default section order.
- Agents should read this guide before drafting new `DEC-*` artifacts.
- Repo-specific truth can still add local detail inside the canonical structure.
```
