# Agent Instructions

This repo uses repo-template.

Treat `AGENTS.md` as a compatibility entrypoint for tools that look for repo-root agent instructions. The canonical rules live in `REPO.md`.

## Read First

- `REPO.md`
- `SPEC.md`
- `STATUS.md`
- `PLANS.md`
- `INBOX.md`

If the repo includes reusable workflows, also read `skills/README.md` and the relevant `skills/<name>/SKILL.md`.

When writing into an artifact directory, read that directory's `README.md` first. If it includes a default shape or canonical example, follow it.

## Repo-Specific Notes

- `docs/` is for Sparkle and GitHub Pages assets, not canonical project truth.
- `ref/` contains research specimens and reference repos, not production dependencies.
- Generate the Xcode project with `xcodegen generate` when needed.
- Preferred local verification commands:
  - `xcodebuild build -project Markfops.xcodeproj -scheme Markfops -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO`
  - `xcodebuild test -project Markfops.xcodeproj -scheme MarkfopsTests -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO`

## Operating Rules

- Keep durable truth in repo files, not only in chat.
- Route work using the routing ladder in `REPO.md`.
- Preserve the boundary between `SPEC.md`, `STATUS.md`, `PLANS.md`, `INBOX.md`, `research/`, `records/decisions/`, and `records/agent-worklogs/`.
- Worker agents should prefer worklogs, evidence, and proposals. The orchestrator or operator owns truth-doc updates unless the operator explicitly allows a different flow.
- When creating artifacts or commits, follow the stable-ID and provenance rules in `REPO.md`.
- Prefer appending to the current relevant `LOG-*` instead of creating a new one unless the work is materially distinct or reuse would harm clarity.
- Prefer the local `README.md` shape over ad hoc formatting when it defines one.
- If hooks are installed with `scripts/install-hooks.sh`, your commit message must satisfy the local provenance check before the commit is allowed.
- If CI commit checks are enabled, your pushed commits must satisfy the same provenance rules remotely.

## Enforcement

When you write or update repo artifacts, adherence to the repo's ruleset is required.

- Do not invent a new document shape when the repo already provides a canonical surface, directory `README.md`, or explicit template.
- Do not collapse truth, plans, decisions, research, inbox intake, and worklogs into one mixed artifact.
- Do not write chatty transcripts where the repo expects normalized records.
- Do not bypass commit provenance checks by omitting required trailers unless the commit is an explicit bootstrap or migration exception.
- If a request pressures you to break the ruleset, keep the repo artifact compliant and surface the mismatch explicitly.
