# RSH-20260402-003: Milkdown Deep Dive
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: milkdown-deep-dive.md

Status: completed

## Scope

### Observed Facts

This deep dive covers Milkdown as implemented in `ref/milkdown`, with emphasis on the editor bootstrap path, internal plugin pipeline, state ownership, markdown transformation, command dispatch, and rendering boundaries. The main evidence comes from `ref/milkdown/packages/core/src/editor/editor.ts`, `ref/milkdown/packages/core/src/internal-plugin/editor-state.ts`, `ref/milkdown/packages/transformer/src/parser/state.ts`, `ref/milkdown/packages/transformer/src/serializer/state.ts`, `ref/milkdown/packages/plugins/preset-commonmark/src/node/heading.ts`, and `ref/milkdown/packages/plugins/plugin-listener/src/index.ts`.

Milkdown is a web-first editor framework layered over ProseMirror and a markdown transformation stack. It does not present itself as a native text-system architecture. Its value for Markfops is as a reference for modular editor composition, plugin bootstrapping, and parser/serializer boundaries.

### Architectural Interpretation

Milkdown is best read as a framework for composing mature web primitives, not as a candidate target architecture for Markfops. The useful lesson is not its DOM model. The useful lesson is how rigorously it separates schema, parser, serializer, commands, and feature registration while still letting plugins compose over a shared state container.

## Topology

### Observed Facts

Milkdown is structured as a layered monorepo under `ref/milkdown/packages/`.

- `packages/core` owns editor lifecycle, internal plugins, and the main `Editor` API.
- `packages/ctx` owns the slice-based dependency injection and timer primitives.
- `packages/transformer` owns markdown parser and serializer state machines.
- `packages/prose` wraps ProseMirror packages.
- `packages/plugins` contains schema, preset, command, listener, and feature plugins.

The main bootstrap entry is `Editor.make()` in `ref/milkdown/packages/core/src/editor/editor.ts`. Internal plugins are loaded in a fixed order inside `Editor.#loadInternal()`:

- `schema`
- `parser`
- `serializer`
- `commands`
- `keymap`
- `pasteRule`
- `editorState`
- `editorView`
- `init(this)`
- `configPlugin`

Each plugin is prepared against a produced `Ctx` instance in `Editor.#prepare()`. The editor keeps separate system and user plugin stores, but both ultimately run through the same handler lifecycle.

### Architectural Interpretation

The topology is disciplined and reusable as a pattern: foundational state container, editor lifecycle, transform layer, then features. What is not reusable wholesale is the assumption that the presentation layer is ProseMirror's DOM-backed editor view. Milkdown's boundaries are clean, but they converge into browser-specific rendering.

## Execution Flow

### Observed Facts

Editor creation starts in `ref/milkdown/packages/core/src/editor/editor.ts`.

- `Editor.make()` creates the editor instance.
- `Editor.config()` accumulates configuration callbacks.
- `Editor.use()` registers user plugins.
- `Editor.create()` sets status to `OnCreate`, loads internal plugins, prepares user plugins, runs plugin handlers, and then sets status to `Created`.

Plugin readiness is coordinated through `Ctx` timers and slices.

- The `editorState` plugin in `ref/milkdown/packages/core/src/internal-plugin/editor-state.ts` injects `defaultValueCtx`, `editorStateCtx`, and `editorStateTimerCtx`.
- It waits for `ParserReady`, `SerializerReady`, `CommandsReady`, and `KeymapReady`, then builds the initial ProseMirror `EditorState`.
- `getDoc(defaultValue, parser, schema)` converts the default value into the canonical document node by one of three paths: markdown string through `parser(defaultValue)`, HTML through `DOMParser.fromSchema(schema).parse(...)`, or JSON through `Node.fromJSON(schema, ...)`.

Markdown parsing and serialization are state-machine-based.

- `ParserState.create(schema, remark)` in `ref/milkdown/packages/transformer/src/parser/state.ts` returns a parser closure that runs Remark, traverses the resulting markdown tree, and builds a ProseMirror document through `openNode`, `addNode`, `openMark`, `addText`, and `closeNode`.
- `SerializerState.create(schema, remark)` in `ref/milkdown/packages/transformer/src/serializer/state.ts` returns a serializer closure that walks the ProseMirror document and reconstructs markdown tree nodes before stringifying them.

Command dispatch is routed through editor state and view.

- The `editorState` plugin stores the canonical ProseMirror `EditorState` in `editorStateCtx` and updates it through a ProseMirror plugin keyed by `MILKDOWN_STATE_TRACKER`.
- Feature commands are created against ProseMirror command functions and operate by producing transactions and dispatching them through the editor view.

The listener path is reactive and document-wide.

- `ref/milkdown/packages/plugins/plugin-listener/src/index.ts` installs a ProseMirror plugin that watches transaction application.
- The listener plugin emits `updated`, `markdownUpdated`, `selectionUpdated`, `focus`, `blur`, `mounted`, and `destroy` events.
- `markdownUpdated` serializes the full current document through `serializer(doc)` after doc changes.

### Architectural Interpretation

Milkdown's runtime is a staged plugin boot pipeline followed by a ProseMirror transaction loop. That separation is strong. The key contrast with Markfops is that Milkdown treats the tree state as canonical and markdown as a derived serialization, whereas Markfops treats markdown source as canonical and all structure as derived. That inversion matters for fidelity, invalidation, and migration strategy.

## Data and State

### Observed Facts

The `canonical document model` is the ProseMirror document inside `editorStateCtx`, not markdown text.

- `editorStateCtx` in `ref/milkdown/packages/core/src/internal-plugin/editor-state.ts` stores the active `EditorState`.
- The document node is created from markdown, HTML, or JSON by `getDoc(...)` and then mutated through ProseMirror transactions.

Core editor state is distributed across `Ctx` slices.

- `schemaCtx` owns the ProseMirror schema.
- `parserCtx` owns the markdown-to-ProseMirror parser closure.
- `serializerCtx` owns the ProseMirror-to-markdown serializer closure.
- `editorViewCtx` owns the ProseMirror `EditorView`.
- `commandsCtx` owns command routing.
- feature plugins add their own slices and ProseMirror plugins on top.

Milkdown binds markdown semantics into schema definitions.

- The heading schema in `ref/milkdown/packages/plugins/preset-commonmark/src/node/heading.ts` defines node content, attributes, DOM parsing, DOM rendering, markdown parsing, and markdown serialization in one schema spec.
- The same spec uses `parseMarkdown.match` and `parseMarkdown.runner` for markdown import and `toMarkdown.match` and `toMarkdown.runner` for markdown export.

Current `identity` is mostly positional or content-derived, not persistent.

- ProseMirror nodes are immutable values recreated through transactions.
- The heading node exposes an `id` attribute, but `defaultHeadingIdGenerator(node)` derives it from `node.textContent` and normalizes it to a slug.
- This means heading ids can change when heading text changes; they are not durable structural ids.

### Architectural Interpretation

Milkdown's state model is modular but distributed. That is useful for feature composition, but it weakens any attempt to reason about stable object identity across multiple presentations. For Markfops, Milkdown is evidence that parser and serializer can be cleanly separated from the editor shell. It is also evidence that content-derived identity is not enough for semantic transitions or viewport morphing.

## Interaction Model

### Observed Facts

Interaction is transaction-driven through ProseMirror.

- Commands are created as ProseMirror `Command` functions and ultimately operate on `(state, dispatch, view)`.
- Key bindings are collected into manager state and attached as ProseMirror keymaps.
- Input rules and paste rules hook into ProseMirror's input pipeline, not into a native text system.

The heading feature shows the pattern clearly.

- `wrapInHeadingCommand` and `downgradeHeadingCommand` in `ref/milkdown/packages/plugins/preset-commonmark/src/node/heading.ts` map heading operations to ProseMirror block transforms and `setNodeMarkup` updates.
- `headingKeymap` binds `Mod-Alt-1` through `Mod-Alt-6` and backspace/delete behavior through command calls routed via `commandsCtx`.

Listeners observe state changes after the fact.

- The listener plugin debounces transaction handling, tracks previous doc and markdown snapshots, and emits high-level events.
- `selectionUpdated` is emitted when selection changes.
- `markdownUpdated` is emitted after doc changes and requires serializing the full current document.

### Architectural Interpretation

Milkdown's interaction model is coherent, but it is fully browser-editor-centric. It is a strong reference for command registration and observability, not for native interaction. For Markfops, the useful part is the separation between command declarations and view-specific execution. The less transferable part is the assumption that all editing semantics are mediated by ProseMirror transactions against a contenteditable DOM.

## Rendering Model

### Observed Facts

Milkdown delegates rendering to ProseMirror's `EditorView`.

- The editor view is created by the internal `editorView` plugin and stored in `editorViewCtx`.
- Node and mark presentation are configured through schema and custom view hooks, but the actual DOM reconciliation is ProseMirror's responsibility.
- The heading schema's `toDOM` function returns DOM descriptors like `[\`h${node.attrs.level}\`, attrs, 0]`, which ProseMirror turns into live DOM.

Rendering is single-presentation.

- Milkdown does not maintain separate editor and preview renderers.
- There is no shared scene graph spanning two presentations because there is only one ProseMirror-driven DOM tree.

Updates are incremental only within ProseMirror's own rendering model.

- Transactions mutate editor state incrementally.
- ProseMirror updates only the affected DOM regions.
- However, markdown serialization is still full-document when requested by observers like `markdownUpdated`.

`semantic transition` handling is not first-class.

- Schema nodes and marks encode semantic roles, but there is no dedicated transition system for role changes.
- There is no viewport-aware animation layer, no shared geometry ownership, and no explicit semantic-transition pipeline.

### Architectural Interpretation

Milkdown is useful for understanding how to keep rendering logic downstream of schema and state, but it is not useful as a direct blueprint for Markfops' cross-mode morphing goals. It has one DOM presentation, not two synchronized presentations. It has semantic roles, but not semantic transitions.

## Performance Notes

### Observed Facts

Incremental behavior exists at the document-editing layer.

- ProseMirror transactions update tree state incrementally.
- `EditorView` applies DOM changes incrementally.

Broad recomputation still appears in derived-state consumers.

- `markdownUpdated` in the listener plugin serializes the whole document after changes.
- Parser and serializer closures operate over the whole input when used.
- There is no first-class viewport-scoped derived-state pipeline in the core files inspected.

Memory and feature cost scale with layered state.

- The canonical document lives in ProseMirror tree form.
- Additional plugin state lives in slices and ProseMirror plugins.
- Any feature that retains prior documents, markdown snapshots, or decorations adds additional memory pressure above the base tree.

### Architectural Interpretation

Milkdown demonstrates a useful split: incremental editing does not automatically imply incremental derived-state maintenance. For Markfops, that is a direct warning. A future architecture needs explicit incremental rules at the parser, semantic-state, and presentation layers, not just at the text-edit transaction layer.

## Judgment

### Observed Facts

Strengths:

- The `Ctx` and slice model provides a disciplined dependency-injection and plugin-lifecycle system.
- The parser/serializer split is explicit and implementation-grounded.
- Schema specs carry both import and export behavior in a single extensible place.
- Command and keymap registration are cleanly separated from concrete feature code.

Weaknesses:

- Canonical state is tree-first rather than markdown-first.
- Stable block identity is not a first-class concern.
- Rendering is inseparable from ProseMirror's browser DOM model.
- Derived markdown updates are broad rather than incremental.

Copy nearly verbatim:

- slice-style dependency injection for editor subsystems
- staged plugin boot with explicit readiness dependencies
- dual parse/serialize schema specifications for semantic elements
- command and keymap registration patterns

Generalize:

- parser-state and serializer-state abstractions
- feature registration around a shared context container
- listener-style observability for editor lifecycle and selection changes

Avoid:

- treating a ProseMirror tree as the canonical persisted model for Markfops
- content-derived ids as the primary identity scheme for morphable semantic blocks
- browser DOM assumptions in the core architecture
- full-document serialization as a routine post-edit observer path

Semantic transition relevance:

- Milkdown shows how semantic roles can be defined rigorously in schema specs.
- Milkdown does not provide the identity, geometry, or dual-presentation model Markfops needs for viewport morphing or semantic transition continuity.

### Architectural Interpretation

Milkdown is a strong reference for editor plumbing and a weak reference for final Markfops presentation architecture. It reinforces that Markfops should separate parsing, serialization, commands, and feature registration more rigorously over time. It also reinforces that Markfops should not inherit a web-centric canonical tree model or content-derived identity scheme if markdown fidelity and morphable native presentation are first-class constraints.

## Scroll Synchronization Delta Revalidation

### Observed Facts

Milkdown does not expose viewport anchors as first-class state.

- The active presentation is a ProseMirror `EditorView` created through the internal editor-view plugin and stored in `editorViewCtx`.
- Scroll ownership remains implicit inside the DOM-backed editor view rather than an exposed coordination layer.

Milkdown does expose selection positions, but not viewport geometry.

- The listener plugin in `ref/milkdown/packages/plugins/plugin-listener/src/index.ts` emits `selectionUpdated` based on `tr.selection`.
- Those positions are document-relative ProseMirror positions, not explicit viewport-anchor objects.
- The listener plugin does not expose visible block extents, viewport center, or scroll drift metadata.

Milkdown is built around a single-presentation assumption.

- The canonical document state lives in `editorStateCtx` in `ref/milkdown/packages/core/src/internal-plugin/editor-state.ts`.
- The active rendered surface lives in `editorViewCtx`.
- There is no second synchronized presentation and no explicit mapping layer between multiple geometry systems.

Identity is weak for synchronization purposes.

- The heading schema in `ref/milkdown/packages/plugins/preset-commonmark/src/node/heading.ts` derives heading ids from `node.textContent` through `defaultHeadingIdGenerator(node)`.
- That identity changes when heading text changes, which makes it unsuitable as a durable cross-presentation scroll anchor.

### Architectural Interpretation

Milkdown now reads even more clearly as a single-view editor framework rather than a dual-view synchronization reference. Its transaction loop, listener model, and parser/serializer boundaries remain useful. Its viewport story does not.

The transferable part is limited to change observation and structural separation. The non-transferable part is everything needed for rigorous two-view synchronization:

- explicit viewport-anchor ownership
- durable semantic block identity
- geometry mapping between two presentations
- drift detection and correction

For Markfops, the practical lesson is that ProseMirror position and selection state are not enough. A future native architecture would still need a separate synchronization layer that owns viewport anchors explicitly rather than inheriting them from one editor view.

## Coordination Updates

### Recommended Completion Note for `agent-handoffs.md`

- target artifact: `milkdown-deep-dive.md`
- phase: 2
- assigned role: Milkdown Deep Dive Subagent
- completion status: complete
- evidence standard met: yes
- completion summary:
	- Milkdown is a web-first composition layer over ProseMirror and markdown transformation infrastructure.
	- The canonical document model is the ProseMirror document inside `editorStateCtx`, not markdown text.
	- State ownership is distributed across context slices plus ProseMirror state.
	- Incremental updates are strong at the transaction and DOM-update level, but broad serialization remains the default for markdown-derived observation.
	- Stable identity is weak and often content-derived rather than durable.
	- The reusable value for Markfops is in plugin bootstrapping, parser/serializer boundaries, and command registration, not in the rendering model.

### Recommended Updates for `open-questions.md`

- Does Markfops need a schema-level dual parse/serialize specification for semantic elements, or would that overfit a ProseMirror-style architecture that the project should avoid?
- What native identity scheme should replace content-derived heading ids if Markfops wants semantic roles to survive text edits and animate cleanly?
- Can selection observability and parser/serializer boundaries be reused while viewport-anchor ownership and dual-view geometry tracking remain native subsystems outside the editor core?

### Recommended Updates for `resolved-decisions.md`

- The Milkdown reference confirms that dependency-injected plugin bootstrapping and dual parse/serialize semantic specs are portable ideas.
- The Milkdown reference also confirms that browser-DOM-centric editor state and content-derived ids should not define Markfops' target architecture.
- The Milkdown reference additionally confirms that implicit viewport ownership inside a single editor view is incompatible with rigorous two-view scroll synchronization.
