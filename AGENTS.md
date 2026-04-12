# Agent Instructions

This repo uses repo-template.

Treat `AGENTS.md` as the canonical editable agent-instructions file for the repo.
It should enforce repo behavior while deferring canonical policy details to `REPO.md`.

## Read First

- `REPO.md`
- `SPEC.md`
- `STATUS.md`
- `PLANS.md`
- `INBOX.md`
- `skills/README.md`

Before running a repeatable repo workflow, read the relevant `skills/<name>/SKILL.md`. Treat skills as repo-native procedures even when the agent runtime does not auto-load them.

When writing into an artifact directory, read that directory's `README.md` first. If it includes a prescriptive shape, follow it. If it is intentionally lightweight, keep the output lightweight too.

## Operating Rules

- Keep durable truth in repo files, not only in external tools.
- Route work using the routing ladder in `REPO.md`.
- Preserve the boundary between `SPEC.md`, `STATUS.md`, `PLANS.md`, `INBOX.md`, `research/`, `records/decisions/`, commit-backed execution history, and `upstream-intake/`.
- Worker agents should prefer evidence, proposals, and compliant commit-backed execution records. The orchestrator or operator owns truth-doc updates unless the operator explicitly allows a different flow.
- Treat `INBOX.md` as pressure, not a backlog. During inbox review, cluster capture and promote only survived triage.
- Promote sparsely. Do not mirror one evolving thought into research, decisions, plans, spec, status, upstream records, and execution records.
- If the repo tracks upstream on a cadence, use `upstream-intake/` instead of inventing a parallel workflow.
- When creating artifacts or commits, follow the stable-ID and provenance rules in `REPO.md`.
- Prefer the local `README.md` shape over ad hoc formatting when it defines one.
- Your commit message must satisfy the local repo provenance check before the commit is allowed.
- Your pushed commits must satisfy the same provenance rules remotely in CI.
- Treat each committed change as a canonical execution record through `commit: LOG-*`.
- Normal commits must use the structured body keys `timestamp:`, `changes:`, `rationale:`, and `checks:` with `notes:` optional.

## Enforcement

When you write or update repo artifacts, adherence to the repo's ruleset is required.

- Do not invent a new document shape when the repo already provides a canonical surface, directory `README.md`, or explicit template.
- Do not collapse truth, plans, decisions, research, inbox capture, and execution history into one mixed artifact.
- Do not promote exploratory debate into `SPEC.md`, `STATUS.md`, `PLANS.md`, or `records/decisions/` until there is a concise accepted outcome for that layer.
- Do not turn an inbox review into a giant digest of every low-confidence idea. Report counts or clusters when full detail does not protect focus.
- Do not write chatty transcripts where the repo expects normalized records.
- If an artifact guide is intentionally lightweight, do not over-structure the document just to make it look uniform.
- If the repo guidance and the requested output appear to conflict, follow the repo rules and explain the tension in the artifact or handoff.
- Do not bypass commit provenance checks by omitting required trailers unless the commit is an explicit bootstrap or migration exception.
- Do not put `LOG-*` ids inside `artifacts:`.

## Skills

`skills/<name>/SKILL.md` files are reusable procedures for bounded workflows.

- Keep them procedural.
- Do not duplicate canonical repo policy inside them.
- Use them to standardize repeatable tasks, escalation triggers, and output shape.

## Local Divergence

Markfops-specific repo notes:

- `docs/` is for Sparkle and GitHub Pages assets, not canonical project truth.
- `ref/` contains research specimens and reference repos, not production dependencies.
- Generate the Xcode project with `xcodegen generate` when needed.
- Preferred local verification commands:
  - `xcodebuild build -project Markfops.xcodeproj -scheme Markfops -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO`
  - `xcodebuild test -project Markfops.xcodeproj -scheme MarkfopsTests -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO`
