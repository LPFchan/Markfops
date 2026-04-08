# RSH-20260402-009: Target Architecture
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: target-architecture.md

Status: completed

## Objective

Build a Markfops-native editing engine that keeps markdown source canonical while introducing a durable semantic block layer shared by both the native editor and preview. The architecture must preserve native AppKit editing quality, support incremental migration from the current product, and make rigorous dual-view scroll synchronization and semantic transitions first-class rather than bolt-ons.

Core invariants:

- Markdown source remains the only persisted source of truth.
- Every semantic block and transition-relevant inline region has a durable derived identity independent of content text and tree position.
- Editor and preview are separate renderers over one shared semantic scene, not unrelated products of ad hoc reparsing.
- Viewport synchronization is owned by a dedicated coordination layer, not hidden inside either renderer.
- Visible-region work is prioritized over whole-document recomputation.

## Proposed Modules

### 1. Source Document Core

- Owns document lifecycle, file URL, clean or dirty state, save, reload, and canonical markdown text.
- Preserves the current `Document.rawText` style ownership as the persisted truth.

### 2. Semantic Parse Service

- Parses canonical markdown into a derived semantic block graph.
- Produces source spans, heading metadata, block taxonomy, and parser diagnostics.
- Supports dirty-region invalidation planning so unchanged semantic blocks can be retained when possible.

### 3. Semantic Identity Layer

- Assigns durable ids to semantic blocks and transition-relevant inline segments.
- Maintains identity continuity across reparses using source spans, structural matching, and edit-local heuristics.
- Explicitly separates durable ids from navigational ids such as heading slugs or DOM anchors.

### 4. Presentation State Store

- Holds derived view-facing state that should not live in canonical source.
- Owns active heading, viewport anchors, collapsed structure, geometry snapshots, pending transitions, and search or selection mirrors needed across renderers.
- Acts as the bridge between the semantic scene and individual renderers.

### 5. Native Editor Projection

- Keeps AppKit or TextKit as the live editing surface.
- Projects semantic block styling, block gutters, and lightweight block affordances into a native text system or native block-row hybrid.
- Applies only local style or layout updates for changed or visible semantic blocks.

### 6. Preview Projection

- Renders the same semantic block graph into HTML plus DOM structure for WebKit preview.
- Emits durable block ids and source-span-derived metadata into the DOM.
- Supports targeted block-level DOM updates rather than body-wide replacement as the long-term path.

### 7. Synchronization Coordinator

- Owns the dual-anchor model for editor and preview alignment.
- Tracks continuous viewport ratio, primary semantic block anchor, local offset within anchor, and drift state.
- Negotiates editor-originated and preview-originated scroll updates and resolves layout divergence.

### 8. Transition Coordinator

- Owns semantic transition planning for paragraph-to-heading, paragraph-to-quote, paragraph-to-code, and similar transitions.
- Captures pre- and post-update geometry snapshots for visible semantic blocks.
- Schedules block-level or inline-level motion and style interpolation.

### 9. Command and Policy Layer

- Centralizes semantic editing commands such as split, merge, list continuation, block promotion, and heading changes.
- Keeps command registration and keyboard routing separate from view code.
- Allows gradual adoption of block-aware editing while current text editing remains intact.

## Ownership Boundaries

### Canonical Ownership

- `Document`-level source core owns markdown text and persistence.
- No renderer owns canonical content.
- No preview DOM mutation becomes the source of truth directly.

### Derived Ownership

- Semantic Parse Service owns parse results, source spans, and invalidation planning.
- Semantic Identity Layer owns durable ids and block-matching continuity rules.
- Presentation State Store owns cross-renderer UI state such as active anchor, geometry snapshots, and pending transitions.

### Renderer Ownership

- Native Editor Projection owns AppKit selection, IME interaction, undo integration, and editor-local layout data.
- Preview Projection owns DOM layout, WebKit state, and preview-local scroll details.
- Synchronization Coordinator owns shared alignment state and should be the only place that reconciles editor and preview viewport intent.

### Transition Ownership

- Transition Coordinator owns animation eligibility, geometry snapshot lifetimes, and transition scheduling.
- Renderers expose measurable geometry and accept transition instructions; they do not invent transition policy themselves.

### Identity and Anchor Rules

- Durable semantic ids are never derived from heading text, DOM position, or tree path alone.
- Source spans are mapping aids, not full identity.
- Navigational heading slugs remain allowed, but only as secondary anchors.
- Scroll synchronization uses a hybrid anchor model: shared continuous ratio plus durable semantic block anchor plus local offset.

## Rendering and Motion Model

### Rendering Topology

- Editor and preview remain separate presentations.
- Both consume one shared semantic scene derived from markdown source.
- The editor remains the primary interaction surface for source-authoritative editing.

### Editor Model

- Short term: retain the current `NSTextView`-centric editor and incrementally enrich it with semantic block styling and local block affordances.
- Medium term: introduce row-aware or block-aware editor projection for visible semantic blocks where AppKit text-only rendering becomes limiting.

### Preview Model

- Short term: continue HTML preview generation, but shift toward block-id-emitting DOM structure and targeted updates.
- Medium term: replace body-wide HTML swaps with block-scoped DOM patching keyed by semantic block ids.

### Motion Model

- Motion is viewport-first: only visible semantic blocks are required to animate smoothly.
- The Transition Coordinator captures pre- and post-update geometry for visible anchors.
- Direct interpolation is used when identity remains stable and geometry deltas are tractable.
- Hybrid transitions are used when typography or container structure changes materially.
- Discrete swaps are allowed when continuous animation would be visually dishonest or technically fragile.

### Scroll Synchronization Model

- Primary shared state: viewport-center ratio, semantic block anchor id, and anchor-local offset.
- Editor and preview both report their current resolved anchor state into the Synchronization Coordinator.
- Coordinator computes target alignment and drift.
- Small drift is corrected lazily; large drift during mode switches or explicit jumps is corrected immediately.
- Scroll synchronization is considered incorrect unless it can survive typography differences, code blocks, tables, images, and semantic role changes.

## Migration Strategy

### Phase A: Preserve the Existing Shell

- Keep `Document.rawText` canonical.
- Keep current editor and preview surfaces.
- Replace duplicated heading extraction and ad hoc preview metadata with a first semantic parse service.

### Phase B: Introduce Durable Semantic Identity

- Add semantic block graph generation with durable ids and source spans.
- Rewire TOC, active heading, and preview block ids to come from that graph.
- Add tests for identity preservation across edits, splits, merges, and heading promotion.

### Phase C: Introduce Synchronization Coordinator

- Move scroll ownership out of editor and preview adapters into a dedicated coordinator.
- Upgrade from ratio-only sync to hybrid anchor plus ratio sync.
- Add drift detection and correction instrumentation.

### Phase D: Introduce Transition Coordinator

- Generalize the current narrow preview morph hook into a proper transition subsystem for visible semantic blocks.
- Support at least heading promotion, quote promotion, and code-block transitions for viewport-visible content.

### Phase E: Introduce Block-Aware Native Editing

- Incrementally add block-aware row ownership or semantic overlays to the native editor where plain text editing becomes insufficient.
- Keep markdown round-trip safety and undo behavior as non-negotiable constraints.

### Version Split

- Version 1 should deliver: markdown-first semantic parse service, durable semantic block ids, improved preview patching, hybrid scroll anchors, and a minimal semantic transition pipeline for a small set of constructs.
- Version 2 can deliver: broader block-aware editing, richer multi-block interaction, more aggressive viewport virtualization, and deeper command or plugin surfaces.
