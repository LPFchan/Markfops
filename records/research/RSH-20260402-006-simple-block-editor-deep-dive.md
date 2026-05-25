# RSH-20260402-006: SimpleBlockEditor Deep Dive
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: simple-block-editor-deep-dive.md

Status: completed

## Artifact Provenance

- upstream URL: https://github.com/hot666666/SimpleBlockEditor
- checked-out branch: main
- commit SHA: 7b54bb0b6bd0bb7854ca837bcbf3f66ab1b8bceb

## Scope

### Observed Facts

SimpleBlockEditor is a native macOS block editor built in Swift with AppKit, wrapped in a minimal SwiftUI host. The README describes it as a simple Notion-style text editor, explicitly calls out AppKit, Observation-based change detection, a pluggable `BlockEditingPolicy`, and a pluggable `BlockStore`.

The main evidence comes from:

- `README.md`
- `SimpleBlockEditor/ContentView.swift`
- `SimpleBlockEditor/SimpleBlockEditorApp.swift`
- `SimpleBlockEditor/Model/BlockNode.swift`
- `SimpleBlockEditor/Model/EditorBlockManager.swift`
- `SimpleBlockEditor/Model/EditorCommand.swift`
- `SimpleBlockEditor/Model/EditorEvent.swift`
- `SimpleBlockEditor/Protocol/BlockEditingPolicy.swift`
- `SimpleBlockEditor/Protocol/Impl/BlockEditingPolicyImpl.swift`
- `SimpleBlockEditor/Protocol/BlockStore.swift`
- `SimpleBlockEditor/Protocol/Impl/BlockStoreImpl.swift`
- `SimpleBlockEditor/View/Host/BlockEditorHost.swift`
- `SimpleBlockEditor/View/Host/BlockEditorViewController.swift`
- `SimpleBlockEditor/View/Row/BlockRowCoordinator.swift`
- `SimpleBlockEditor/View/Row/BlockRowController.swift`
- `SimpleBlockEditor/View/Row/BlockRowInputRouter.swift`
- `SimpleBlockEditor/View/Row/BlockRowView.swift`
- `SimpleBlockEditor/View/Components/BlockTextView.swift`
- `SimpleBlockEditor/View/Components/BlockGutterView.swift`
- `SimpleBlockEditorTests/BlockManagerPolicyTests.swift`
- `SimpleBlockEditorTests/BlockManagerStoreTests.swift`
- `SimpleBlockEditorTests/BlockRowInputRouterTests.swift`

The repository is tightly scoped. It is about block editing, stable block identity, focus routing, and AppKit composition. It does not attempt markdown parsing, markdown serialization, preview rendering, or two-view coordination.

### Architectural Interpretation

This is the cleanest native block-editor specimen in the reference set. It is valuable precisely because of its narrow scope. The tradeoff is equally clear: it models semantic blocks directly rather than preserving markdown as the canonical document format. That makes it highly relevant to identity, block composition, and editing-policy questions, but only partially relevant to Markfops' markdown-first constraints.

## Topology

### Observed Facts

Ownership is explicit and layered.

- `ContentView` owns one `EditorBlockManager`.
- `BlockEditorHost` bridges SwiftUI into `BlockEditorViewController`.
- `BlockEditorViewController` owns the scroll view, flipped clip view, stack view, and a `BlockRowCoordinator`.
- `BlockRowCoordinator` owns row-controller lifecycle through a `[UUID: BlockRowController]` map.
- Each `BlockRowController` owns one `BlockRowView`, one `BlockTextView`, a `BlockRowInputRouter`, and a `BlockRowCommandApplier`.

The main model and protocol seams are also explicit.

- `BlockNode` is the semantic block model.
- `EditorBlockManager` owns the canonical `nodes` array plus focus and event queues.
- `BlockEditingPolicy` turns key events into `EditorCommand` values using the `BlockEditingContext` interface.
- `BlockStore` abstracts persistence and external synchronization.

### Architectural Interpretation

The topology is strong because each layer does one job. State ownership, event routing, row lifecycle, and text-view manipulation are separated rather than collapsed into one controller. This is a good reference for block-oriented decomposition in AppKit.

## Execution Flow

### Observed Facts

Startup is minimal.

- `SimpleBlockEditorApp` creates `ContentView`.
- `ContentView` creates `EditorBlockManager()` and passes it into `BlockEditorHost`.
- `BlockEditorHost.makeNSViewController(...)` instantiates `BlockEditorViewController(manager:)`.

View-controller bootstrapping is explicit.

- `BlockEditorViewController.loadView()` builds an `NSScrollView`, a flipped `NSClipView`, and a vertical `NSStackView`.
- `viewWillAppear()` starts store sync, seeds initial rows through `configureInitialRowsIfNeeded()`, and begins Observation-based event draining.

Mutation flow runs through the manager and policy seam.

- `BlockTextView.keyDown(with:)` forwards key handling to `keyEventHandler` unless IME composition is active.
- `BlockRowController.handleKeyEvent(_:)` asks `BlockRowInputRouter` whether the key is an in-block text event, a soft break, or a semantic editor event.
- Semantic events go to `delegate?.rowController(... commandFor:event,node:)`.
- That call reaches `EditorBlockManager.command(for:node:)`, which invokes `policy.makeEditorCommand(...)`.
- The default policy mutates through `BlockEditingContext` operations such as `split`, `merge`, `update`, and returns an `EditorCommand` describing view-local edits, caret moves, or focus changes.
- `BlockRowCommandApplier.apply(_:)` executes those commands on the current `BlockTextView` and propagates focus changes upward.

Text updates and store propagation are separated.

- `textDidChange(_:)` in `BlockRowController` updates `node.text` and schedules a debounced notify path.
- The coordinator forwards updates to `EditorBlockManager.update(node:)`.
- The manager applies the mutation, enqueues an `EditorBlockEvent`, and optionally publishes a `BlockStoreEvent` when the origin is local.
- `observeNodeEvents()` drains and clears the pending event queue so `BlockEditorViewController` can update rows incrementally.

### Architectural Interpretation

The control flow is unusually disciplined for a small prototype. Policy decides intent, the manager owns structural mutations, commands perform immediate text-view effects, and the view controller only reconciles row presentation. That separation is worth reusing. The main limitation is that the execution flow assumes the canonical model is already a semantic block array, not source markdown.

## Data and State

### Observed Facts

`canonical document model` is the manager-owned block array, not markdown text.

- `EditorBlockManager` stores `nodes: [BlockNode]` as its canonical content state.
- `BlockNode` is a reference type with durable `id: UUID`, mutable `kind: BlockKind`, mutable `text: String`, and optional `listNumber`.
- Equality on `BlockNode` is identity-by-UUID.

The semantic model is intentionally small.

- `BlockKind` supports `.paragraph`, `.heading(level:)`, `.bullet`, `.ordered`, and `.todo(checked:)`.
- `EditorCommand` is ephemeral command state for immediate view mutation, not a persisted model.
- `EditorBlockEvent` is a structural event queue for insert, update, remove, move, and focus changes.
- `BlockStoreEvent` is the persistence and synchronization event contract.

Transient state is localized.

- `focusedNodeID` tracks block-level focus.
- `pendingNodeEvents` buffers structural events until the observation loop drains them.
- `BlockTextView` keeps caret and selection locally and exposes `BlockCaretInfo` snapshots when policy decisions need exact position data.

Prototype boundaries are visible.

- `DefaultBlockStore` is a stub that returns one heading block and only logs events.
- `DefaultBlockEditingPolicy` implements heading, bullet, and todo space triggers but does not yet implement ordered-list triggers; the README still lists ordered policy as TODO.

### Architectural Interpretation

This is the strongest identity model in the reference set for block-oriented editing. Durable block IDs exist by default, and structural operations keep identity explicit. The price is that markdown source, syntax, and serializer boundaries do not exist here. Markfops can borrow the identity and mutation architecture, but not the document model wholesale.

## Interaction Model

### Observed Facts

Interaction is block-scoped and policy-driven.

- `BlockRowInputRouter` intercepts return, space, delete, and arrow keys when they imply block-level meaning.
- Shift-return becomes a soft line break and stays within the current text view.
- Space-trigger parsing in `DefaultBlockEditingPolicy` converts leading `#`, `##`, `###`, `-`, `*`, `[]`, `[ ]`, and `[x]` patterns into semantic block kinds.
- Enter splits the current block and focuses the new sibling.
- Backspace at the start demotes non-paragraph blocks to paragraph, or merges paragraph content into the previous block.
- Arrow navigation escapes to adjacent blocks only at structural boundaries.
- Todo checkbox toggles in `BlockGutterView` bypass the debounce path and update immediately.

Selection is local, not document-global.

- Each block owns its own `NSTextView` selection.
- Focus changes are represented as `EditorFocusEvent` values and routed through the manager and coordinator.
- There is no multi-block selection model in the inspected code.

### Architectural Interpretation

This is a practical Notion-like interaction model for a native block editor. The key strength is that semantic operations are explicit and overridable through policy rather than being spread across view code. The main limitation for Markfops is that these interactions operate on already-semantic blocks, not on markdown syntax that must remain round-trippable.

## Rendering Model

### Observed Facts

Rendering is AppKit-native and row-oriented.

- `BlockEditorViewController` uses a vertical `NSStackView` inside a flipped scroll view.
- `BlockRowView` lays out `BlockGutterView` and `BlockTextView` side by side and updates constraints based on whether the current kind uses a gutter.
- `BlockTextView` computes intrinsic height from `layoutManager.usedRect(for:)` and invalidates intrinsic size on text changes.
- `BlockGutterView` renders bullets, ordered labels, or todo checkboxes depending on `BlockKind`.
- Styling is derived from `BlockNodeStyle` and `EditorStyle` rather than carried in the model itself.

Update granularity is row-scoped.

- The observation loop drains discrete block events.
- `BlockRowCoordinator` updates, inserts, removes, or focuses only the affected rows.
- Existing row controllers are reused via UUID lookup.

### Architectural Interpretation

This is the best concrete example in the corpus of stable row reuse based on durable block identity. That is highly relevant to viewport morphing work. It still stops short of Markfops' needs because there is no second renderer, no shared geometry model across presentations, and no notion of semantic role transitions from markdown source into preview semantics.

## Performance Notes

### Observed Facts

The code shows deliberate local optimization.

- Observation does not expose the entire nodes array directly; instead, `nodeEventClock` wakes observers and `observeNodeEvents()` drains a buffered event queue.
- `BlockRowCoordinator` keeps controllers keyed by UUID so row instances can be reused rather than rebuilt for every update.
- `BlockRowController` debounces text updates with `Debouncer` at 1500 ms before notifying the manager.
- Store writes are asynchronous and origin-tagged to avoid feedback loops.

The current rendering model is still full-stack-view based.

- All rows live in one `NSStackView`.
- No viewport virtualization or lazy row destruction is present in the inspected code.
- Intrinsic height invalidation depends on TextKit layout measurement for each changed row.

### Architectural Interpretation

For a compact native editor, the architecture is efficient and focused. For very large documents, the lack of virtualization and the one-text-view-per-block model could become expensive. Even so, this repo demonstrates a more plausible path to viewport-scoped updates than the web-first references because identity and row ownership are explicit.

## Judgment

### Observed Facts

Strengths:

- Durable block identity through `BlockNode.id`.
- Clear policy/context split between intent and mutation.
- AppKit-native row composition with strong ownership boundaries.
- Row-controller reuse keyed by UUID.
- Explicit focus routing and caret-position snapshots.
- Tests covering policy, store synchronization, observation, and input routing.

Weaknesses:

- Canonical model is semantic blocks, not markdown text.
- No parser, serializer, or markdown round-trip path.
- No second renderer or preview architecture.
- No multi-block selection or richer document-structure operations.
- Ordered-list policy is not implemented yet despite `.ordered` existing in `BlockKind`.
- Some infrastructure remains prototype-level, especially the default store.

Copy nearly verbatim:

- durable UUID-based block identity on semantic block nodes
- policy/context split where editing rules request mutations through an intention-oriented interface
- row-controller reuse keyed by block id
- explicit focus-change events and caret snapshots as first-class interaction data
- event-queue observation pattern instead of exposing broad mutable state directly

Generalize:

- keep block-level structural mutations centralized in one manager rather than scattering them across text views
- separate transient command application from persistent model mutation
- use AppKit-native row composition and gutter ownership when block semantics materially affect layout
- debounce text persistence while keeping structural navigation immediate

Avoid:

- replacing markdown source with semantic blocks as the canonical document model for Markfops
- assuming one-text-view-per-block scales indefinitely without virtualization or more advanced viewport management
- treating the current prototype store as sufficient persistence architecture
- importing the interaction model wholesale without a markdown-fidelity plan

Semantic transition relevance:

- SimpleBlockEditor is highly relevant to identity preservation across semantic block states because block ids survive style changes, splits, and merges in a controlled way.
- It does not solve transitions from markdown syntax into semantic presentation because markdown syntax is absent.
- It is still the best reference so far for how identity could remain stable while semantic role changes occur at the block level.

Scroll synchronization relevance:

- SimpleBlockEditor offers no direct two-view synchronization evidence because it is single-view only.
- It is still indirectly useful because durable block identity is a prerequisite for any future shared-anchor system between editor and preview.
- It does not provide preview-owned scroll state, cross-render drift correction, or dual-presentation anchor negotiation.

### Architectural Interpretation

SimpleBlockEditor is the most important structural reference in the set for Markfops' future block architecture. It validates that native block identity, policy-driven editing, and row-scoped reuse can be kept clean in AppKit. It does not answer markdown fidelity, dual-view synchronization, or semantic preview transitions by itself. Markfops should borrow the identity and mutation architecture while keeping markdown source canonical and layering preview coordination separately.
