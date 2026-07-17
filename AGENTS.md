# Agent Instructions

`AGENTS.md` is the canonical editable agent-instructions file. It enforces repo behavior while deferring canonical policy to `records/REPO.md`.

## Read First

- `records/REPO.md`
- `records/SPEC.md`
- `records/STATUS.md`
- `records/PLANS.md`
- `records/INBOX.md`
- `skills/README.md`

Before writing into an artifact directory, read its `README.md` and follow its prescriptive shape when it defines one.

## Skills

Load the skill before the trigger condition fires. Each skill defines the procedure; follow it.

| Trigger | Skill |
| --- | --- |
| Before creating a normal commit | `skills/commit-generator/SKILL.md` |
| Before replacing, deleting, or rewriting content that already exists | `skills/clean-correction/SKILL.md` |
| When routing work or creating repo artifacts | `skills/repo-orchestrator/SKILL.md` |
| When reviewing inbox pressure | `skills/daily-inbox-pressure-review/SKILL.md` |
| When reviewing upstream changes | `skills/upstream-intake/SKILL.md` |

Repo-agnostic skills (`sharpen-the-tip`, `prototype-mode`, `housekeeping`, `proactive-docs`) are **global**, not vendored per repo — they live in `~/.agents/skills/` via the `agents` module of LPFchan/setup, and your runtime surfaces them automatically.

## Rules

- Keep durable truth in repo files, not only in external tools.
- Route work using the routing ladder in `records/REPO.md`.
- Preserve the boundary between `records/SPEC.md`, `records/STATUS.md`, `records/PLANS.md`, `records/INBOX.md`, `records/research/`, `records/decisions/`, commit-backed `LOG-*`, and `records/upstream-intake/`.
- Worker agents produce evidence, proposals, and compliant `LOG-*` commits. The orchestrator or operator owns truth-doc updates unless the operator explicitly allows otherwise.
- Treat `records/INBOX.md` as pressure, not a backlog. Cluster capture; promote only survived triage.
- Promote sparsely. Do not mirror one thought into research, decisions, plans, spec, status, upstream, and execution records.
- Every normal commit must be created from a skeleton registered by `scripts/new-commit-message.sh` and must pass local and remote provenance checks.
- Follow the stable-ID and provenance rules in `records/REPO.md`.
- Do not put `LOG-*` ids inside `artifacts:`.
- Do not invent a document shape when the repo already provides a canonical surface, directory `README.md`, or template.
- Do not promote exploratory debate into truth docs or decisions until there is a concise accepted outcome.
- Do not turn an inbox review into a digest of every low-confidence idea. Report counts or clusters.
- Do not write chatty transcripts where the repo expects normalized records.
- Do not bypass commit provenance checks unless the commit is an explicit bootstrap or migration exception.

## Local Divergence

Markfops-specific repo notes:

- `docs/` is for Sparkle and GitHub Pages assets, not canonical project truth.
- `ref/` contains research specimens and reference repos, not production dependencies.
- Generate the Xcode project with `xcodegen generate` when needed.
- Preferred local verification commands:
  - `xcodebuild build -project Markfops.xcodeproj -scheme Markfops -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO`
  - `xcodebuild test -project Markfops.xcodeproj -scheme MarkfopsTests -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO`
