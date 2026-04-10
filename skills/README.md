# Skills

This directory is Markfops' repo-native procedure layer.

Agents should read the relevant workflow even when their runtime does not auto-load skills.

Each reusable workflow should live at `skills/<name>/SKILL.md`.

Required baseline skills:

- `repo-orchestrator/`
  - Generic routing workflow for truth, status, plans, research, decisions, commit-backed execution, and inbox capture.
- `daily-inbox-pressure-review/`
  - Focus-protecting daily triage for `IBX-*` capture and capture packets.

Conditional skills:

- `upstream-intake/`
  - Companion workflow for the optional upstream-review module.
  - Include it when the adopted repo enables `upstream-intake/`; omit it when the repo does not track an upstream.

Keep skills procedural.
Do not duplicate the canonical rules from `REPO.md` inside them.

Use `SKILL.md` for:

- step-by-step procedures
- required inputs and expected outputs
- escalation triggers
- links to supporting templates or reference docs

Do not use `SKILL.md` for:

- repo-wide policy
- general project truth
- local or personal preferences that belong in tool-specific memory files
