---
name: clean-correction
description: "When overwriting existing content, write only the intended replacement — never leave traces of the correction process."
argument-hint: "Target artifact and intended replacement"
---

# Clean Correction

When the operator redirects or corrects an earlier draft, the durable artifact must contain only the final intended content — not a record of how we got there.

## The Rule

Write only what the artifact should say, not what it used to say or how it was changed.

- Do not include `A (not B)`, `A, not B`, `A instead of B`, `A as corrected`, or similar traces.
- Do not paraphrase the operator's correction back into the artifact.
- Do not leave stubs of the previous version behind.

## Procedure

1. Read the target before writing. Know what is being replaced.
2. Write the replacement directly. No commentary about the edit.
3. Verify the result contains only the intended content.

## When To Pause

Pause and ask for clarification instead of guessing when:

- the target boundary is unclear (which part of the file is being replaced?)
- the replacement content is still implicit or underspecified
- the change is large enough that a quick summary of what is going away would help

## Edge Cases

- **Fuzzy corrections** ("make this more casual", "tighten this up"): restate the concrete replacement before writing. Do not just edit and hope.
- **Full rewrites**: write the new version. Do not preserve fragments of the old one to show the transition.
- **Deletions**: delete cleanly. Do not replace deleted content with `// removed` or `[empty]`.
- **Fast-path requests** ("just do it"): write cleanly anyway. The discipline is in the artifact, not the conversation.

## What This Skill Does Not Do

- It does not classify edits as additive or destructive.
- It does not require an explicit confirmation prompt before writing.
- It does not generate diffs for the operator to review.

The point is clean artifacts, not procedural ceremony.
