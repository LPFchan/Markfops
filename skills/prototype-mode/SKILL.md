---
name: prototype-mode
description: Activates when the user is prototyping, building greenfield projects, or explicitly working pre-MVP. Trigger phrases: "we're just prototyping", "greenfield", "pre-MVP", "from scratch", "new project", "spike", "throw it away", "rewrite not refactor", "stop shimming", "just break it". Deactivation: "exit prototype mode", "stop prototype mode".
argument-hint: "Scope (file, directory, or project-wide) and the specific change being made"
---

# Prototype Mode

Use this skill when the user is working on pre-MVP code with no real users or production consumers. Backward compatibility is not a virtue here — it is debt taken on for no reason.

Use it with:

- [../../AGENTS.md](../../AGENTS.md)

This skill governs the posture for breaking changes during prototyping: break interfaces freely, skip bridge layers and migration scaffolding, refactor surgically, and verify every call site is updated.

## What This Skill Produces

- a confirmed scope (file, directory, or project-wide) before breaking changes
- a behavioral comparison (old vs new) before deleting old code
- exhaustive call-site search and update, including docs, config, schemas, and generated code
- baseline-aware verification (type-check, lint, test) after changes
- a self-check before finishing: no shims, no bridge layers, no orphaned references

## Core Rules

### 1. Break freely

When changing an interface, function signature, data shape, or module boundary — just change it. No shims, no old versions. Delete the old thing entirely.

Exception — test oracles: keeping the old function as a golden-reference oracle in tests is fine. Mark with `// TODO: remove oracle after validation` and delete before considering the change complete.

Infrastructure carve-out: treat a file as infrastructure if breaking it would prevent building, running, or deploying. If "if I change this and the project stops building, am I blocked?" → yes → it's infrastructure.

### 2. No bridge layers

No adapter functions, compatibility wrappers, or translation layers between old and new.

### 3. One canonical truth

If a concept exists in two places, ask before consolidating. Intentional duplication is valid; accidental is a bug.

### 4. Refactor minimally

Update the thing that needs to change and all its call sites. Do not rewrite unrelated code.

### 5. No migration scaffolding

No `migrateFooToBar()`, no `if (legacyMode)`. Nothing needs migrating. Forward-looking TODOs (`// TODO: replace hardcoded value with config`) are fine.

### 6. No deprecation scaffolding

Do not mark things `@deprecated` unless explicitly asked.

## Procedure

### Step 0: Baseline

Run the project's test suite and linter to record pre-existing failures.

### Step 1: Read the old code

List observable behaviors: side effects, return values, exceptions thrown, arguments consumed. This is the behavioral contract for step 5.

### Step 2: Locate

Search the full project for all references: source code, configuration, type declaration files, API schemas (OpenAPI, GraphQL, Protobuf), test files, documentation, generated/compiled code directories.

### Step 3: Assess scope

If the change touches more than ~5 distinct modules, tell the user the scope and confirm before proceeding. Below that, proceed but state which files are changing.

### Step 4: Multi-symbol refactors

Produce a behavioral contract per changed symbol. For sweeping refactors, list intended behavioral changes as a whole.

### Step 5: Check behavior

Before deleting old code, compare the new implementation against the behavioral list from step 1. Confirm each behavior is preserved, intentionally removed, or intentionally changed.

### Step 6: Update

Change every call site and reference, including docs (READMEs, API docs, env templates, code comments).

### Step 7: Delete

Remove the old signature/function/shape entirely. Test oracles are the exception — delete those after validation.

### Step 8: Verify

Run type-checker, linter, and tests. Compare against baseline. Fix errors from your changes; report pre-existing unrelated errors.

## Dynamic Languages

In untyped projects, be exhaustive with call-site search. Use multiple strategies: string-based access, metaprogramming, dynamic imports, `eval`. Acknowledge statically unfindable patterns as known risk. Tell the user which files changed. Offer a smoke test if none exist.

## Generated Code

Check for generated code in `target/`, `build/`, `dist/`, `gen/`, `__generated__/`. If generated code references the changed symbol, warn the user — the fix is in the source schema, not the output.

## File-Scoped Mode

When scope is a single file but external call sites exist, find and update them. Do not leave them broken. If touching production code, get user confirmation first.

## Escalation Triggers

Escalate to the operator when:

- scope is ambiguous (the repo contains both prototype and production code)
- a concept exists in two places and it's unclear whether duplication is intentional
- the change touches more than ~5 distinct modules
- real-consumer signals are present (published packages, inbound API calls, users with production data)
- a breaking change would require coordinated migration across multiple parties

## Quality Bar

- no bridge layers, compatibility shims, or migration scaffolding left behind
- every call site is located and updated before the old code is deleted
- behavioral comparison (step 5) happens before deletion
- baseline-aware verification runs after every change
- self-check passes: no "if old", no deprecated, no orphaned references
