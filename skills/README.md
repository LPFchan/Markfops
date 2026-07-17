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
- `clean-correction-gate/`
  - Confirmation workflow for destructive edits so replacements stay explicit and durable artifacts stay free of correction-history bleed.

Conditional skills:

- `upstream-intake/`
  - Companion workflow for the optional upstream-review module.
  - Include it when the adopted repo enables `records/upstream-intake/`; omit it when the repo does not track an upstream.
- `sharpen-the-tip/`
  - Iterative artifact refinement via neutral-subagent review loop.
  - Include it when the repo uses structured review cycles for plans, specs, or other artifacts.
- `prototype-mode/`
  - Pre-MVP posture: break interfaces freely, skip bridge layers and migration scaffolding, refactor surgically.
  - Include it when the repo contains greenfield or pre-production code.
- `housekeeping/`
  - Read-only adversarial repository-boundary audit: inventory the full physical workspace, verdict every artifact, propose a gated migration.
  - Include it when the repo accumulates generated artifacts, caches, backups, or ignored residue that need periodic justification.

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
