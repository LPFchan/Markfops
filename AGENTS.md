<!-- template-managed:begin -->
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
| When reviewing upstream changes *(only if the optional `records/upstream-intake/` module is enabled)* | `skills/upstream-intake/SKILL.md` |

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

## Engineering Principles

- Find the real constraint, then fight for the smallest model.
- Don't add machinery just because it looks thorough.
- Security matters, but don't over-index on it.

## Pull Requests

- One problem per PR.
- Be ready to push back on review findings. Dismiss false positives with a one-line reason.

## Code Review Rules

- Review against the Engineering Principles above.
- Only flag a race or edge case if it can realistically happen in how this repo actually runs.
- Don't review commit provenance on PRs; `scripts/merge-pr.sh` validates the squash commit that lands.
<!-- template-managed:end -->