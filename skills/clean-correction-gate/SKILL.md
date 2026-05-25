---
name: clean-correction-gate
description: "Pause before overwriting existing content so destructive edits stay clean, explicit, and free of correction-history bleed."
argument-hint: "Target artifact and proposed replacement content"
---

# Clean Correction Gate

Use this skill before replacing, deleting, or rewriting content that already exists.

Use it with:

- [../../AGENTS.md](../../AGENTS.md)

This skill keeps document content clean when a user corrects or redirects an earlier draft.
Its job is to stop correction-history bleed such as writing `A (not B)` into the durable artifact
instead of writing only `A`.

## What This Skill Produces

- a quick classification of the write as additive or destructive
- an explicit confirmation gate before destructive replacement
- a clean final write that contains only the intended replacement content

## Core Rule

`additive` means writing into empty space or creating a new target. Proceed without a confirmation gate.

`destructive` means replacing, removing, moving, or rewriting content that already exists. Read first, then confirm before writing.

When in doubt, treat the operation as destructive.

## Procedure

1. Read the current target state.
   - For files or docs, read the relevant section or the whole file when it is small.
   - For structured content, read the specific field, key, or block that will change.
   - If the target does not exist yet, classify the write as additive and proceed.

2. Classify the write.
   - New file, new section, or append-only addition: additive.
   - Partial replacement, full rewrite, deletion, or source-side move: destructive.

3. Gate destructive edits before writing.
   - Show the literal existing content being replaced.
   - Show the literal proposed replacement content.
   - Keep the prompt about the content only. Do not include conversation history, rationale, or correction commentary.
   - Use this shape:

```text
[path/to/file] - line [A] to [B] :
"""
[existing content excerpt]
"""

replacing with :
"""
[new content excerpt]
"""

continue? yes / no / show full diff
```

4. Handle the response.
   - `yes`: perform the write, then confirm briefly in chat.
   - `no`: do not write; wait for new instruction.
   - `show full diff`: present the full before/after diff, then re-present the confirmation gate.
   - Anything ambiguous: clarify before proceeding.

5. Write cleanly after confirmation.
   - The artifact should contain only the final intended content.
   - Never include traces like `as corrected`, `instead of the previous version`, or `not B`.

## Edge Cases

- Fuzzy corrections such as "make this more casual": restate the concrete replacement first, then gate the destructive edit.
- Full rewrites: say it is a full rewrite and show a short excerpt from both versions before asking to continue.
- Deletions: show the content being removed and make the replacement explicit as nothing.
- Fast-path requests such as "just do it": keep at least a minimal one-line destructive-edit notice before proceeding.

## Escalation Triggers

Escalate instead of guessing when:

- the target boundary is unclear
- multiple destructive edits should happen and the safe grouping is not obvious
- the replacement content is still implicit or underspecified

## Quality Bar

- always read before classifying
- always gate destructive replacements before writing
- keep the gate literal and compact
- keep final artifact content free of correction-history debris
