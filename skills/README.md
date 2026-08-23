# Skills

This directory is part of the repo-template scaffold.

Use it as repo-native procedural documentation.
Agents should read the relevant workflow even when their runtime does not auto-load skills.

Each reusable workflow should live at `skills/<name>/SKILL.md`.

Required baseline skills:

- `repo-orchestrator/`
  - Generic routing workflow for truth, status, plans, research, decisions, commit-backed execution, and inbox capture.
- `daily-inbox-pressure-review/`
  - Focus-protecting daily triage for `IBX-*` capture and capture packets.
- `commit-generator/`
  - Commit scaffold workflow for repo-compliant `LOG-*` commits.
  - Use it when an agent needs to create a normal commit message without guessing the required structure or provenance fields.
- `clean-correction/`
  - Writing rule for destructive edits: write only the intended replacement, keep durable artifacts free of correction-history bleed.

Conditional skills:

- `upstream-intake/`
  - Companion workflow for the optional upstream-review module.
  - Include it when the adopted repo enables `records/upstream-intake/`; omit it when the repo does not track an upstream.

## Global skills (not vendored here)

Repo-agnostic workflows — `sharpen-the-tip`, `prototype-mode`, `housekeeping`, `proactive-docs` — are **not** copied into each repo. They live globally in `~/.agents/skills/` (installed by the `agents` module of LPFchan/setup) and the runtime surfaces them everywhere. This scaffold only carries skills that are bound to repo-template's own records/commit machinery.

Keep skills procedural.
Do not duplicate the canonical rules from `records/REPO.md` inside them.

Use `SKILL.md` for:

- step-by-step procedures
- required inputs and expected outputs
- escalation triggers
- links to supporting templates or reference docs

Do not use `SKILL.md` for:

- repo-wide policy
- general project truth
- local or personal preferences that belong in tool-specific memory files
