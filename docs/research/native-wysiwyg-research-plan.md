# Markfops Native WYSIWYG Research Plan

## Purpose

This document defines the research program for building a lightweight, AppKit-based, Notion-like WYSIWYG markdown engine for Markfops. The goal is not to chase a generic editor architecture. The goal is to identify the smallest native architecture that can preserve markdown as the source of truth, feel native on macOS, stay memory-efficient, support progressive movement toward block-oriented editing, morph visible text objects smoothly between editor and preview presentations, and dynamically morph markdown semantics inside the preview presentation itself.

This plan treats external repositories as reference specimens, not product dependencies. They are here to teach architecture, tradeoffs, and implementation patterns.

The main agent for this program is orchestration-only. It should coordinate the work, maintain the research documents, launch narrow subagent passes, and judge output quality, but it should not perform the primary repo archaeology itself except for minimal document-quality checks or contradiction resolution.

## Main Objective

Build a native AppKit-based WYSIWYG markdown engine for Markfops that:

- keeps markdown as the canonical document format
- feels like a native macOS text system component rather than a web app embedded in a shell
- remains lightweight in memory and responsive for long documents
- supports a path from inline rich markdown editing toward more Notion-like block behavior
- morphs text objects within the viewport smoothly between editor and preview mode at 60 fps, with a stretch goal of 120 fps on supported hardware
- dynamically morphs plain text into markdown semantics in preview mode, including headings, quotes, inline code, code blocks, lists, emphasis, and other supported markdown constructs
- avoids the preview-to-source corruption class of bugs by design

## Sub Objectives

- Understand Markfops' current editor, renderer, preview, and document state architecture in exhaustive detail.
- Evaluate Milkdown as a behavioral and architectural reference, not as a direct implementation base.
- Evaluate Intend, Inkdown, and SimpleBlockEditor as native reference materials once cloned into `ref/`.
- Identify which ideas are safe to copy nearly verbatim, which ideas should only be generalized, and which ideas should be avoided.
- Define how visible text and block objects keep stable identity across editor and preview presentations so they can animate cleanly.
- Define how a normal text object can transition into markdown semantic roles without discontinuity in preview mode.
- Produce a target architecture for Markfops with clear module boundaries, invariants, and migration steps.
- Build a prioritized backlog of implementation spikes and risk-reduction experiments.

## Core Principles

- Markdown source of truth: rendered presentation must never silently become the canonical model.
- Native-first: prefer AppKit and text-system primitives over web primitives when the feature can be implemented cleanly natively.
- Incremental work: prefer paragraph-, block-, and viewport-scoped updates over full-document relayout or reparsing.
- Stable identity before animation: smooth transitions should come from shared object identity and layout data, not from screenshot cross-fades.
- Viewport-first motion: only visible content must meet the morphing frame budget; offscreen content can update lazily.
- Semantic transitions are first-class: heading promotion, quote promotion, code styling, and other markdown presentation shifts should be modeled as transitions between semantic states, not as abrupt style replacement.
- Separation of concerns: parsing, model, rendering, interaction, and persistence should be separable and testable.
- Evidence over aesthetics: every design choice should be justified by code archaeology, measured behavior, or direct failure modes.
- Reference, not cargo cult: external repos are inputs to understanding, not templates to transplant wholesale.

## Non Goals

- Port Milkdown to AppKit line-for-line.
- Adopt any external reference repository as a direct dependency of Markfops.
- Solve every future editor feature before defining the core native document and layout model.
- Optimize for cross-platform reuse at the cost of native clarity.

## Research Questions

The research should answer these questions concretely:

1. What should the native editor's canonical internal model be: plain markdown text, parsed block graph, attributed text projection, or a hybrid?
2. Which operations can be incremental and cheap, and which must trigger broader recomputation?
3. How should inline markdown hiding and rich presentation coexist with accurate source editing?
4. When should Markfops behave like Typora, and when should it behave like Notion?
5. Where do block boundaries live: parser, editor model, layout layer, or interaction layer?
6. How should markdown round-trip fidelity be preserved across editing commands?
7. Which AppKit or TextKit limitations require architectural workarounds?
8. What identity model is required so visible text and block objects can morph cleanly between editor and preview states?
9. What layout, animation, and invalidation pipeline is required to sustain 60 fps and preferably 120 fps for viewport-scoped mode transitions?
10. How should plain text transition into semantic markdown presentations such as H1, H2, H3, quotes, inline code, code blocks, and lists while the user is working in preview mode?
11. What is the minimum viable native architecture that can ship before full block editing exists?

## Reference Corpus

### Current Markfops Codebase

- `Markfops/App`
- `Markfops/State`
- `Markfops/Editor`
- `Markfops/Renderer`
- `Markfops/Parsing`
- `Markfops/Views`
- `Markfops/Commands`

### Reference Repositories

- `ref/milkdown`
- `ref/intend` once cloned
- `ref/inkdown` once cloned
- `ref/SimpleBlockEditor` once cloned

### Expected Roles of Each Reference

- `milkdown`: mature markdown-oriented editor decomposition, schema and transformer layering, plugin boundaries, feature packaging
- `intend`: native inline markdown rendering, parser-renderer separation, AppKit-first editor pipeline, incremental editing ideas
- `inkdown`: compact native architecture, NSTextView-based inline formatting behavior, minimal overhead design choices
- `SimpleBlockEditor`: AppKit-native block composition, Notion-like interaction hints, block data and view coordination patterns

## Deliverables

The research task is complete only when it produces the following artifacts.

1. A Markfops baseline architecture document.
2. One deep-dive archaeology document per reference repository.
3. A cross-reference comparison matrix.
4. A transferability matrix with three buckets:
   - copy nearly verbatim
   - generalize the idea
   - avoid
5. A target Markfops native editor architecture proposal.
6. A phased implementation roadmap with validation checkpoints.
7. A viewport morphing strategy document covering object identity, shared layout data, animation ownership, and frame-budget assumptions.
8. A semantic transition coverage document listing which markdown constructs can morph continuously, which require hybrid transitions, and which require discrete transitions.
9. A risk register covering fidelity, performance, AppKit/TextKit limits, animation smoothness, and migration risks.

## Expected Output Layout

Store future outputs in `docs/research/` using stable filenames.

- `docs/research/native-wysiwyg-research-plan.md`
- `docs/research/README.md`
- `docs/research/orchestration-status.md`
- `docs/research/agent-handoffs.md`
- `docs/research/open-questions.md`
- `docs/research/resolved-decisions.md`
- `docs/research/markfops-baseline.md`
- `docs/research/milkdown-deep-dive.md`
- `docs/research/intend-deep-dive.md`
- `docs/research/inkdown-deep-dive.md`
- `docs/research/simple-block-editor-deep-dive.md`
- `docs/research/comparison-matrix.md`
- `docs/research/transferability-matrix.md`
- `docs/research/target-architecture.md`
- `docs/research/implementation-roadmap.md`
- `docs/research/viewport-morphing-strategy.md`
- `docs/research/semantic-transition-coverage.md`
- `docs/research/risk-register.md`

## Methodology

### Methodology 1: Exhaustive Code Archaeology

Goal: understand each codebase down to module-by-module, type-by-type, function-by-function, and important variable-by-variable behavior.

For each repository:

- Map the full module and package tree.
- Identify entry points, initialization flow, editor bootstrapping, and data ownership.
- Catalog important types, classes, structs, protocols, and their responsibilities.
- Trace important functions and methods, especially around editing, parsing, rendering, selection, input handling, scrolling, and persistence.
- Note critical state variables, caches, flags, and mutation boundaries.
- Identify what is synchronous, asynchronous, incremental, memoized, or deferred.
- Record invariants and assumptions the code relies on.
- Extract failure-prone areas, workarounds, and hidden complexity.

Required depth standard:

- Do not stop at package-level summaries.
- Do not stop at README architecture claims.
- Read implementation files directly.
- Prefer code path tracing over narrative interpretation.
- Capture concrete file paths, type names, method names, and control flow.

### Methodology 2: Strength and Weakness Analysis

Goal: separate attractive demos from durable architecture.

For each repository and for each major subsystem:

- Identify what it does well.
- Identify where complexity is concentrated.
- Identify signs of architectural leverage versus accidental cleverness.
- Identify likely performance or memory hazards.
- Identify coupling that would be expensive in Markfops.
- Identify product-quality gaps, unfinished edges, or fragile assumptions.

Every deep-dive should include these sections:

- strengths
- weaknesses
- what to avoid for Markfops
- what to strive for in Markfops

### Methodology 3: Transferability Analysis

Goal: determine what can be brought over directly, what can be generalized, and what is architecture-bound.

Every noteworthy implementation detail should be classified into one of these buckets:

- Copy nearly verbatim: ideas that are local, robust, and architecture-agnostic enough to lift with minimal change.
- Generalize: ideas whose core principle is valuable, but whose implementation is tied to specific libraries, web APIs, or project structure.
- Avoid: ideas that create hidden coupling, poor fidelity, poor native feel, memory overhead, or long-term maintenance pain.

Examples of things to classify:

- parser invalidation strategy
- selection mapping strategy
- viewport rendering strategy
- shared object identity and geometry strategy
- semantic state transition strategy
- block identity scheme
- inline token hiding logic
- markdown serializer boundaries
- command dispatch model
- plugin registration model
- editor state ownership
- bridge layers between UI and model

### Methodology 4: Comparative Synthesis

Goal: synthesize the reference corpus into a Markfops-native architecture rather than a pile of notes.

This stage should answer:

- what Markfops should borrow from each reference
- what Markfops should reject from each reference
- what minimum architecture is sufficient for version 1
- what can wait for version 2 or later

Output format:

- one cross-reference matrix
- one target architecture proposal
- one prioritized implementation roadmap

### Methodology 5: Validation by Implementation Planning

Goal: ensure the research terminates in shippable engineering work.

Every synthesis pass must convert findings into concrete next steps:

- define module boundaries for new Markfops native editor components
- define ownership of markdown source, parsed representation, and presentation state
- define ownership of object identity, geometry snapshots, and mode-transition animation state
- define how semantic roles such as paragraph, heading, quote, and code are represented for transition purposes
- define first spike projects
- define test strategy
- define performance measurement points
- define migration path from current editor and preview arrangement

### Methodology 6: Viewport Morphing and Frame-Budget Analysis

Goal: determine how the future engine can morph visible text objects between editor and preview mode smoothly enough to feel native at 60 fps and ideally 120 fps.

This work should answer:

- what counts as a morphable text object or block object
- where stable identity for those objects is created and maintained
- whether editor and preview are distinct renderers, dual projections of one layout model, or two styles over one presentation tree
- how semantic role changes are represented so a paragraph can become a heading, quote, or code presentation without losing identity
- what geometry, style, and content data must be shared to avoid flicker or discontinuity
- which transitions can be interpolated directly and which need discrete swaps
- how viewport clipping, scrolling, selection, IME, and cursor state affect animation correctness
- what the CPU and GPU budget per frame must be on 60 Hz and 120 Hz displays

Required outputs:

- a proposed morphing pipeline for viewport content
- a list of animation blockers in AppKit or TextKit
- a measurement plan for dropped frames, layout churn, and invalidation frequency
- a recommendation on whether editor and preview should remain separate modes internally or become two presentations of one native scene

### Methodology 7: Semantic Markdown Transition Coverage

Goal: define how the engine should morph plain text into specific markdown semantics while the user is working in preview mode.

This work should classify supported markdown constructs into transition categories:

- continuously morphable: transitions that should animate directly through shared geometry and style interpolation
- hybrid morphable: transitions that need partial interpolation plus controlled discrete swaps
- discrete only: transitions that should not fake continuity because doing so would look wrong or break editing correctness

The coverage analysis should include at minimum:

- headings H1 through H6
- strong and emphasis
- inline code
- fenced code blocks
- blockquotes
- ordered and unordered lists
- task lists
- links
- thematic breaks
- tables where supported

For each construct, answer:

- what is the source semantic role before the transition
- what is the target semantic role after the transition
- what identity stays stable
- what geometry changes
- what typography changes
- whether the transition should be character-level, line-level, block-level, or container-level
- whether the syntax tokens remain editable, hidden, ghosted, or separately animated

## Deep-Dive Template

Each repo-specific research document should follow the same template.

### 1. Scope

- repository purpose
- maturity level
- why it matters to Markfops

### 2. Topology

- top-level modules
- important internal boundaries
- key dependencies

### 3. Execution Flow

- startup path
- editor creation path
- document load path
- input event path
- parse/render/update path
- save/serialize path

### 4. Data and State

- canonical model
- derived models
- caches
- mutable state holders
- invalidation triggers

### 5. Interaction Model

- selection and caret handling
- keyboard commands
- block interactions
- drag and drop
- scrolling and viewport behavior

### 6. Rendering Model

- text rendering strategy
- block rendering strategy
- incremental update strategy
- layout invalidation behavior
- mode transition and morphing behavior
- semantic role transition behavior

### 7. Performance Notes

- obvious hot paths
- likely memory pressure points
- incremental optimizations
- expensive abstractions
- animation and frame-budget risks

### 8. Judgment

- strengths
- weaknesses
- copy nearly verbatim
- generalize
- avoid
- semantic transition relevance

## Recommended Research Phases

### Phase 0: Prepare the Reference Set

- clone `milkdown`, `intend`, `inkdown`, and `SimpleBlockEditor` into `ref/` as needed
- record upstream URL, branch, and commit SHA for each
- avoid modifying reference repos unless a temporary local patch is required for inspection

### Phase 1: Baseline Markfops Archaeology

- document current editor, renderer, preview, and document flow
- capture existing strengths to preserve
- capture architectural pain points that motivate a native WYSIWYG engine

### Phase 2: Reference Repo Deep Dives

- analyze `milkdown`
- analyze `intend`
- analyze `inkdown`
- analyze `SimpleBlockEditor`

### Phase 3: Cross-Reference Synthesis

- produce comparison matrix
- produce transferability matrix
- define Markfops-native architectural direction

### Phase 4: Implementation Framing

- define module plan for Markfops
- define MVP scope
- define spike backlog
- define test and measurement strategy
- define viewport morphing spike and frame-budget instrumentation strategy
- define semantic-transition spike coverage for core markdown constructs

## Inter-Agent Communication Protocol

All coordination should happen through documents in `docs/research/`.

Required coordination files:

- `orchestration-status.md`: current phase, active assignment, next assignment, blockers
- `agent-handoffs.md`: assignment payloads and completion notes for subagents
- `open-questions.md`: unresolved questions that affect research direction
- `resolved-decisions.md`: decisions that should not be rediscovered in later phases

Rules:

- The main agent writes assignments and state updates into the coordination files.
- Subagents read their assignment from the coordination files and write findings back into their assigned artifact documents.
- The main agent should base its next actions on the research documents and coordination files, not on a growing conversational summary.
- Direct chat prompts to subagents should be thin wrappers that point them at the relevant files in `docs/research/`.
- The main agent may perform light verification reads of the output documents, but it should not absorb the actual archaeology workload.

## Best Delegation Structure

The best structure is a hub-and-spoke model.

### Hub: Main Agent

Responsibilities:

- maintain the canonical research plan, coordination files, and output documents
- define exact scope for each subagent pass
- assign work through the coordination files in `docs/research/`
- prevent duplicated effort and shallow summaries
- reconcile contradictions between subagent findings
- convert research into Markfops-specific architectural decisions
- ensure repo-specific subagents own the clone-and-setup step for their target repositories under `ref/`

The main agent should not spend most of its time on broad repo search. It should spend its time on orchestration, synthesis, quality control, and turning findings into engineering direction. It should not perform the primary repo-level research itself.

All spoke roles are defined directly in the copy-paste prompts below. The prompts are the source of truth for each subagent's scope, focus, expected inputs, and output artifact.

## Delegation Order

Run the work in this order:

1. Markfops baseline
2. Milkdown deep dive
3. Intend deep dive
4. Inkdown deep dive
5. SimpleBlockEditor deep dive
6. Cross-repo synthesis
7. Main agent writes target architecture and roadmap

Rationale:

- The baseline must come first because all judgments are relative to Markfops.
- Milkdown comes early because it provides the richest decomposition vocabulary.
- The native references come next because they reveal what is realistic in AppKit.
- Cross-repo synthesis should happen after the repo-specific archaeology is already concrete.

## Copy-Paste Prompt: Main Agent

Use the main agent as the orchestrator for the full research program.

Prompt:

```text
- Read docs/research/native-wysiwyg-research-plan.md, docs/research/orchestration-status.md, docs/research/agent-handoffs.md, docs/research/open-questions.md, and docs/research/resolved-decisions.md before starting.
- Operate as the main orchestration agent for this research program.
- Stay orchestration-only. Do not perform the primary repo archaeology yourself.
- Keep the canonical coordination state in docs/research/orchestration-status.md, docs/research/agent-handoffs.md, docs/research/open-questions.md, and docs/research/resolved-decisions.md.
- Launch narrow read-only subagent passes instead of doing the research work directly.
- Make the repo-specific subagents responsible for cloning and setting up their target repositories under ref if those repositories are missing.
- Require every subagent artifact to cite concrete file paths, symbol names, state ownership, and control-flow evidence.
- Reject outputs that stop at README summaries, folder listings, or vague architectural commentary.
- Normalize terminology across repositories so equivalent concepts are compared consistently.
- Separate observed facts from architectural interpretation.
- Do not let web-specific implementation details dominate the target architecture merely because Milkdown is more mature.
- Preserve focus on Markfops constraints: native feel, markdown fidelity, memory efficiency, incremental migration, viewport morphing quality, and semantic transition quality.
- Follow the delegation order in the plan.
- Start by updating the coordination files and delegating only Phase 1: the Markfops baseline deep dive.
- Do not let scope expand to external reference repos before the baseline artifact is complete.
- After each subagent report, update the comparison and transferability artifacts when the plan calls for them.
- Use docs/research documents as the communication layer with subagents.
```

## Copy-Paste Prompt: Markfops Baseline Subagent

Use the `Explore` agent.

Prompt:

```text
- Read docs/research/native-wysiwyg-research-plan.md, docs/research/orchestration-status.md, docs/research/agent-handoffs.md, docs/research/open-questions.md, docs/research/resolved-decisions.md, and docs/research/markfops-baseline.md before starting.
- Treat this as a deep read-only archaeology pass.
- No external repository cloning is required for this pass because the target is the current Markfops codebase.
- Read code directly, not just README files.
- Prefer tracing actual control flow over summarizing folder names.
- Identify ownership of data, mutation points, update triggers, caches, and invariants.
- Report concrete implementation details with file paths and symbol names.
- Distinguish between architecture and incidental implementation.
- Evaluate whether the architecture could support stable object identity and 60 or 120 fps viewport morphing.
- Evaluate whether the architecture could support clean semantic transitions for markdown constructs without breaking editing correctness.
- Call out uncertainty explicitly instead of guessing.
- Analyze the Markfops codebase as the target environment for a future native AppKit-based Notion-like WYSIWYG markdown engine.
- Be exhaustive.
- Produce a deep architecture report that maps modules, important types, state ownership, editor flow, preview flow, markdown render flow, and document lifecycle.
- Trace concrete control flow for document load, edit, parse, render, preview update, save, selection, scroll sync, and mode switches.
- Identify existing invariants, coupling, migration constraints, extension points, current constraints on smooth viewport-scoped morphing between editor and preview presentations, and current constraints on semantic markdown transitions such as paragraph-to-heading or paragraph-to-quote in preview mode.
- Do not stop at directory summaries.
- Write document-quality findings back into docs/research/markfops-baseline.md.
- Add a short completion note to docs/research/agent-handoffs.md.
- End the artifact with these required sections: strengths, weaknesses, copy nearly verbatim, and generalize or avoid.
- Thoroughness: thorough.
```

## Copy-Paste Prompt: Milkdown Deep-Dive Subagent

Use the `Explore` agent.

Prompt:

```text
- Read docs/research/native-wysiwyg-research-plan.md, docs/research/orchestration-status.md, docs/research/agent-handoffs.md, docs/research/open-questions.md, docs/research/resolved-decisions.md, and docs/research/milkdown-deep-dive.md before starting.
- Treat this as a deep read-only archaeology pass.
- Ensure the target repository exists at ref/milkdown.
- If ref/milkdown is missing, clone the official Milkdown repository into ref/milkdown before analysis.
- Record the upstream URL, checked-out branch, and commit SHA in docs/research/milkdown-deep-dive.md before or alongside the findings.
- Do not modify the reference repository beyond cloning and any minimal setup needed to inspect it.
- Read code directly, not just README files.
- Prefer tracing actual control flow over summarizing folder names.
- Identify ownership of data, mutation points, update triggers, caches, and invariants.
- Report concrete implementation details with file paths and symbol names.
- Distinguish between architecture and incidental implementation.
- Evaluate whether the architecture could support stable object identity and 60 or 120 fps viewport morphing.
- Evaluate whether the architecture could support clean semantic transitions for markdown constructs without breaking editing correctness.
- Call out uncertainty explicitly instead of guessing.
- Analyze ref/milkdown as a reference architecture for a future native AppKit-based markdown WYSIWYG engine.
- Be obsessive and code-driven.
- Go package by package, then type by type where necessary.
- Focus on core, ctx, prose, transformer, plugins, components, crepe, and integrations.
- Identify initialization flow, editor state ownership, schema and transformer layering, plugin registration, command flow, feature packaging, markdown round-trip boundaries, and any concepts that could generalize into stable object identity, smooth presentation morphing, or semantic markdown transitions such as paragraph-to-heading and paragraph-to-code styling.
- Separate what is genuinely architecturally valuable from what is web- or ProseMirror-specific.
- Write document-quality findings back into docs/research/milkdown-deep-dive.md.
- Add a short completion note to docs/research/agent-handoffs.md.
- End the artifact with these required sections: strengths, weaknesses, copy nearly verbatim, and generalize or avoid.
- Thoroughness: thorough.
```

## Copy-Paste Prompt: Intend Deep-Dive Subagent

Use the `Explore` agent.

Prompt:

```text
- Read docs/research/native-wysiwyg-research-plan.md, docs/research/orchestration-status.md, docs/research/agent-handoffs.md, docs/research/open-questions.md, docs/research/resolved-decisions.md, and docs/research/intend-deep-dive.md before starting.
- Treat this as a deep read-only archaeology pass.
- Ensure the target repository exists at ref/intend.
- If ref/intend is missing, clone the official Intend repository into ref/intend before analysis.
- Record the upstream URL, checked-out branch, and commit SHA in docs/research/intend-deep-dive.md before or alongside the findings.
- Do not modify the reference repository beyond cloning and any minimal setup needed to inspect it.
- Read code directly, not just README files.
- Prefer tracing actual control flow over summarizing folder names.
- Identify ownership of data, mutation points, update triggers, caches, and invariants.
- Report concrete implementation details with file paths and symbol names.
- Distinguish between architecture and incidental implementation.
- Evaluate whether the architecture could support stable object identity and 60 or 120 fps viewport morphing.
- Evaluate whether the architecture could support clean semantic transitions for markdown constructs without breaking editing correctness.
- Call out uncertainty explicitly instead of guessing.
- Analyze ref/intend as a native macOS inline markdown editor reference for Markfops.
- Focus on editor bootstrapping, NSDocument ownership, parsing strategy, incremental parsing, NSTextView or NSTextStorage design, attribute rendering, inline syntax hiding, selection behavior, sidebar and TOC integration, preview integration if any, and save pipeline.
- Judge whether the architecture could support smooth viewport-scoped morphing between editor and preview presentations plus semantic transitions such as paragraph-to-heading or paragraph-to-quote in preview mode.
- Prioritize concrete symbols, state variables, and control flow over README-level summary.
- Write document-quality findings back into docs/research/intend-deep-dive.md.
- Add a short completion note to docs/research/agent-handoffs.md.
- End the artifact with these required sections: strengths, weaknesses, copy nearly verbatim, and generalize or avoid.
- Thoroughness: thorough.
```

## Copy-Paste Prompt: Inkdown Deep-Dive Subagent

Use the `Explore` agent.

Prompt:

```text
- Read docs/research/native-wysiwyg-research-plan.md, docs/research/orchestration-status.md, docs/research/agent-handoffs.md, docs/research/open-questions.md, docs/research/resolved-decisions.md, and docs/research/inkdown-deep-dive.md before starting.
- Treat this as a deep read-only archaeology pass.
- Ensure the target repository exists at ref/inkdown.
- If ref/inkdown is missing, clone the official Inkdown repository into ref/inkdown before analysis.
- Record the upstream URL, checked-out branch, and commit SHA in docs/research/inkdown-deep-dive.md before or alongside the findings.
- Do not modify the reference repository beyond cloning and any minimal setup needed to inspect it.
- Read code directly, not just README files.
- Prefer tracing actual control flow over summarizing folder names.
- Identify ownership of data, mutation points, update triggers, caches, and invariants.
- Report concrete implementation details with file paths and symbol names.
- Distinguish between architecture and incidental implementation.
- Evaluate whether the architecture could support stable object identity and 60 or 120 fps viewport morphing.
- Evaluate whether the architecture could support clean semantic transitions for markdown constructs without breaking editing correctness.
- Call out uncertainty explicitly instead of guessing.
- Analyze ref/inkdown as a minimal native macOS inline markdown editor reference for Markfops.
- Be implementation-focused.
- Trace how it parses markdown, maps AST ranges to editor ranges, applies attributes, hides syntax for inactive lines, updates presentation during editing, and keeps the architecture lightweight.
- Identify what is elegant, what is brittle, what scales poorly if the design evolves toward a Notion-like block model, and whether its rendering model could support smooth viewport-scoped morphing between editor and preview states plus semantic transitions for markdown constructs like headings, quotes, and code.
- Write document-quality findings back into docs/research/inkdown-deep-dive.md.
- Add a short completion note to docs/research/agent-handoffs.md.
- End the artifact with these required sections: strengths, weaknesses, copy nearly verbatim, and generalize or avoid.
- Thoroughness: thorough.
```

## Copy-Paste Prompt: SimpleBlockEditor Deep-Dive Subagent

Use the `Explore` agent.

Prompt:

```text
- Read docs/research/native-wysiwyg-research-plan.md, docs/research/orchestration-status.md, docs/research/agent-handoffs.md, docs/research/open-questions.md, docs/research/resolved-decisions.md, and docs/research/simple-block-editor-deep-dive.md before starting.
- Treat this as a deep read-only archaeology pass.
- Ensure the target repository exists at ref/SimpleBlockEditor.
- If ref/SimpleBlockEditor is missing, clone the official SimpleBlockEditor repository into ref/SimpleBlockEditor before analysis.
- Record the upstream URL, checked-out branch, and commit SHA in docs/research/simple-block-editor-deep-dive.md before or alongside the findings.
- Do not modify the reference repository beyond cloning and any minimal setup needed to inspect it.
- Read code directly, not just README files.
- Prefer tracing actual control flow over summarizing folder names.
- Identify ownership of data, mutation points, update triggers, caches, and invariants.
- Report concrete implementation details with file paths and symbol names.
- Distinguish between architecture and incidental implementation.
- Evaluate whether the architecture could support stable object identity and 60 or 120 fps viewport morphing.
- Evaluate whether the architecture could support clean semantic transitions for markdown constructs without breaking editing correctness.
- Call out uncertainty explicitly instead of guessing.
- Analyze ref/SimpleBlockEditor as an AppKit-native Notion-like block editor reference for Markfops.
- Focus on the block data model, block identity, block storage, editor view composition, event propagation, selection behavior, editing policies, parser hooks, what enables or limits Notion-like interactions, whether the block architecture could support stable cross-mode object identity for smooth viewport morphing, and whether it can preserve identity across semantic markdown role changes.
- Judge how much of the repo is architecture versus prototype.
- Write document-quality findings back into docs/research/simple-block-editor-deep-dive.md.
- Add a short completion note to docs/research/agent-handoffs.md.
- End the artifact with these required sections: strengths, weaknesses, copy nearly verbatim, and generalize or avoid.
- Thoroughness: thorough.
```

## Copy-Paste Prompt: Cross-Repo Synthesis Subagent

Use the `Explore` agent only after the repo-specific notes exist.

Prompt:

```text
- Read docs/research/native-wysiwyg-research-plan.md, docs/research/orchestration-status.md, docs/research/agent-handoffs.md, docs/research/open-questions.md, docs/research/resolved-decisions.md, docs/research/markfops-baseline.md, docs/research/milkdown-deep-dive.md, docs/research/intend-deep-dive.md, docs/research/inkdown-deep-dive.md, docs/research/simple-block-editor-deep-dive.md, docs/research/comparison-matrix.md, docs/research/transferability-matrix.md, docs/research/target-architecture.md, docs/research/viewport-morphing-strategy.md, docs/research/semantic-transition-coverage.md, and docs/research/risk-register.md before starting.
- Treat this as a synthesis pass driven by the research documents, not a loose summary.
- Ensure the required reference repositories exist under ref/ before synthesis.
- If any of ref/milkdown, ref/intend, ref/inkdown, or ref/SimpleBlockEditor are missing, clone the missing repositories before synthesizing so the artifact set and reference set stay aligned.
- Record any clone-and-setup actions in docs/research/agent-handoffs.md.
- Prefer tracing concrete evidence in the existing artifacts over restating high-level repository descriptions.
- Distinguish between observed facts and architectural judgment.
- Evaluate whether the combined evidence supports stable object identity, 60 or 120 fps viewport morphing, and clean semantic transitions for markdown constructs without breaking editing correctness.
- Call out uncertainty explicitly instead of guessing.
- Compare canonical model choices, parsing and invalidation strategies, rendering strategies, selection mapping, block identity, command architecture, plugin or extension boundaries, performance risks, migration implications, support for smooth viewport-scoped morphing between editor and preview presentations, and support for semantic markdown transitions such as paragraph-to-heading, paragraph-to-quote, and paragraph-to-code.
- Force architectural judgment.
- Update docs/research/comparison-matrix.md, docs/research/transferability-matrix.md, docs/research/target-architecture.md, docs/research/viewport-morphing-strategy.md, docs/research/semantic-transition-coverage.md, and docs/research/risk-register.md as needed.
- Add a short completion note to docs/research/agent-handoffs.md.
- Ensure the updated artifacts include these required sections somewhere: strengths, weaknesses, copy nearly verbatim, and generalize or avoid.
- Thoroughness: thorough.
```

## Quality Bar for Research Outputs

Reject and redo any output that has these failure modes:

- mostly README paraphrase
- mostly folder listing
- little or no symbol-level detail
- no control-flow tracing
- no discussion of state ownership
- no distinction between observed facts and inferred judgments
- no Markfops-specific implications

Acceptable outputs should make it possible to answer questions like these immediately:

- which type owns the canonical model
- which function applies inline rendering after an edit
- which state variables gate expensive work
- where block identity is created and persisted
- where selection and caret mapping can drift from the source model
- where serialization boundaries are enforced or violated
- where stable object identity for morphing could live
- what would likely prevent 60 or 120 fps viewport transitions
- what would likely prevent clean paragraph-to-heading, paragraph-to-quote, or paragraph-to-code transitions

## Practical Notes

- Use the main agent for orchestration, synthesis, and documentation quality control only.
- Use the `Explore` subagent for deep read-only archaeology passes.
- Let each repo-specific subagent own cloning and setup of its target repository under ref when needed.
- Use fast search tools only to narrow file scope before deeper reading; do not mistake search hits for understanding.
- Keep reference repos isolated under `ref/` and avoid mixing them into Markfops build paths.
- Record commit SHAs in every deep-dive document so future analysis remains reproducible.
- Keep coordination state in documents under `docs/research/`, not in chat history.

## Exit Criteria

This research plan has succeeded when:

- every reference repo has a deep-dive document
- the documents are concrete enough to support implementation work without redoing basic archaeology
- the comparison and transferability matrices are complete
- a target Markfops architecture exists
- the first implementation spikes are defined in a prioritized order
- the viewport morphing strategy is explicit and measurable
- the supported semantic markdown transitions are explicit and categorized
- the team can explain not just what to build, but why alternative patterns were rejected