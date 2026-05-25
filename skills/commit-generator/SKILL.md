---
name: commit-generator
description: "Generate and validate repo-compliant commit messages using the local scaffold script and standards checker."
argument-hint: "Commit subject and optional metadata such as agent, role, or artifacts"
---

# Commit Generator

Use this skill when you need to create a normal repo commit and want to follow the repo's required `LOG-*` commit format without guessing.

Use it with:

- [../../scripts/new-commit-message.sh](../../scripts/new-commit-message.sh)
- [../../scripts/check-commit-standards.sh](../../scripts/check-commit-standards.sh)
- [../../records/REPO.md](../../records/REPO.md)
- [../../AGENTS.md](../../AGENTS.md)

## What This Skill Produces

- a fresh commit message scaffold with a unique primary `LOG-*` id
- a registered primary `LOG-*` id that the local `prepare-commit-msg` hook will accept
- a validated normal commit message with the required structured body keys
- a repeatable agent workflow for commit creation instead of ad hoc message drafting

## When To Use It

Use this skill for normal commits that should carry the standard repo provenance body:

- `timestamp:`
- `changes:`
- `rationale:`
- `checks:`
- `notes:` when needed
- `project:`, `agent:`, `role:`, and `commit:` trailers

Do not use this skill as a substitute for the commit checker. The script generates and registers the scaffold; the hooks and checker remain the enforcement gate.

## Procedure

1. Choose the commit subject and metadata.
   - Pick a concise subject line.
   - Set `--agent`, `--role`, and optional `--artifacts` when they differ from the defaults.

2. Generate a fresh scaffold.
   - Run `sh scripts/new-commit-message.sh --subject "..." --agent <agent-id>`.
   - Use a fresh scaffold instead of reusing an old temp file so the `LOG-*` id is new and locally registered.

3. Fill in the body.
   - Replace the `TODO` entries under `changes:`, `rationale:`, and `checks:`.
   - Keep entries short, factual, and specific to the committed work.

4. Validate before commit.
   - Run `sh scripts/check-commit-standards.sh <path-to-message>`.
   - If validation fails because the `commit:` id already exists, generate a new scaffold instead of editing the old `LOG-*` manually.

5. Commit with the validated message.
   - Run `git commit -F <path-to-message>`.
   - Do not use `git commit -m ...`; the repo hook should reject normal commits that did not come from the generator.

6. Clean up temporary scaffold files when they are no longer needed.

## Agent Guidance

When you are about to make a normal commit, prefer this flow over hand-writing the commit body from scratch.

If the operator asks you to commit, the safe default is:

1. stage the intended files
2. generate a fresh scaffold
3. fill it in
4. validate it
5. commit with it

## Escalation Triggers

Escalate instead of guessing when:

- the correct `role:` or `artifacts:` values are ambiguous
- the commit should be an exception to the normal commit-body format
- the operator wants a multi-commit split and the boundaries are unclear
- the commit content spans policy, truth-doc promotion, or another layer that may need orchestrator handling

## Quality Bar

- always use a fresh scaffold for a fresh commit
- never bypass the validator for a normal commit
- keep `changes:`, `rationale:`, and `checks:` concrete and auditable
- treat the script as the generator and the checker as the gate
