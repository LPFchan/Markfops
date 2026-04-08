See @repo-operating-model.md for the canonical repo operating rules.

# Claude Code Memory

This file exists so Claude Code can discover the repo's working rules automatically.

Treat `CLAUDE.md` as a thin compatibility layer, not a second source of truth. The canonical rules stay in `repo-operating-model.md`.

Also consult:

- `SPEC.md` for durable product truth
- `STATUS.md` for current operational reality
- `PLANS.md` for accepted future direction
- `INBOX.md` for untriaged intake

When writing into `research/` or `records/`, consult the local `README.md` first and mirror its default shape or canonical example by default.

Repo-specific reminders:

- `docs/` is reserved for Sparkle and GitHub Pages assets.
- `ref/` contains reference specimens, not production dependencies.
- Use `xcodegen generate` if the Xcode project needs regeneration.
- Prefer the documented `xcodebuild` build and test commands from `AGENTS.md` or `README.md` for verification.

## Enforcement

When producing repo documents, you must enforce the repo's writing rules rather than treating them as suggestions.

- Use the canonical surface for the job.
- Follow the local `README.md` shape or explicit template when one exists.
- Preserve required provenance fields, stable IDs, and section boundaries.
- Do not replace normalized repo artifacts with freeform chat summaries.
- If commit hooks are enabled, produce a compliant commit message rather than treating hook failures as optional.
- If CI commit checks are enabled, assume non-compliant pushed commits will be rejected downstream and fix the message instead of working around the check.
- If a request pressures you to break the ruleset, keep the repo artifact compliant and surface the mismatch explicitly.
