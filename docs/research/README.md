# Markfops Research Workspace

This directory stores the working research artifacts for the native AppKit-based WYSIWYG markdown engine initiative described in `docs/research/native-wysiwyg-research-plan.md`.

These files are intended to accumulate concrete findings, not brainstorming fragments. Each document should be updated incrementally as research progresses.

The main agent for this effort is orchestration-only. It should coordinate the work and maintain the research documents, but it should delegate the actual repo archaeology to subagents.

## Expected Artifacts

- `native-wysiwyg-research-plan.md`
- `orchestration-status.md`
- `agent-handoffs.md`
- `open-questions.md`
- `resolved-decisions.md`
- `markfops-baseline.md`
- `milkdown-deep-dive.md`
- `intend-deep-dive.md`
- `inkdown-deep-dive.md`
- `simple-block-editor-deep-dive.md`
- `comparison-matrix.md`
- `transferability-matrix.md`
- `target-architecture.md`
- `implementation-roadmap.md`
- `viewport-morphing-strategy.md`
- `semantic-transition-coverage.md`
- `risk-register.md`

## Working Rules

- Prefer concrete code evidence over summary prose.
- Record upstream commit SHAs for reference repositories.
- Separate observed facts from architectural interpretation.
- Keep terminology consistent across all research documents.
- Treat external repositories as reference specimens, not dependencies.
- Keep inter-agent communication inside `docs/research/` documents.
- Use `orchestration-status.md` and `agent-handoffs.md` as the operational control plane.
- Use `open-questions.md` and `resolved-decisions.md` as the canonical decision memory for the research program.