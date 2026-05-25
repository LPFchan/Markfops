# RSH-20260402-007: Comparison Matrix
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: comparison-matrix.md

Status: completed

## Scope

This matrix synthesizes the accepted artifacts for the current Markfops baseline plus the four reference specimens: Milkdown, Intend, Inkdown, and SimpleBlockEditor. The goal is not to crown a winner. The goal is to compare how each specimen handles the architectural axes that matter to Markfops: markdown fidelity, native feel, stable identity, incremental work, semantic transitions, and rigorous two-view synchronization.

## Axes

- canonical model
- parsing and invalidation
- rendering strategy
- interaction model
- block identity
- viewport morphing feasibility
- semantic transition support
- memory and performance implications
- migration fit for Markfops

## Matrix

| Axis | Markfops Baseline | Milkdown | Intend | Inkdown | SimpleBlockEditor | Synthesis Implication |
| --- | --- | --- | --- | --- | --- | --- |
| canonical model | Plain markdown source in `Document.rawText` | ProseMirror document in `editorStateCtx` | Plain markdown source in `MarkdownDocument.source` | Slate schema in `IDoc.schema` | Semantic block array in `EditorBlockManager.nodes` | Markfops should keep markdown canonical and add derived semantic structure, not replace source with a tree-first model. |
| parsing and invalidation | Full preview rerender, line-scoped syntax highlight, whole-document heading parse | Transactional tree edits, but broad markdown serialization for observation | Pure parse boundary, intended dirty-block invalidation, current full reparse fallback | Worker-based import or export, but schema-first editing and broad render path | No markdown parser; block semantics are direct model state | The target needs a pure parse boundary plus incremental block invalidation over markdown-derived structure. |
| rendering strategy | Native AppKit editor plus WKWebView preview; separate layout engines | Single browser DOM editor view | Native attributed editor plus WKWebView preview | Electron plus React plus Slate; read-only second Slate rendering | AppKit stack of block rows and text views | Markfops should remain native and keep editor plus preview separate renderers, but both must share durable semantic identity and a synchronization layer. |
| interaction model | Native text editing first, preview mostly passive, narrow preview-side heading promotion | Transaction-driven browser commands | Source-first native editor, passive preview | Schema-editor interactions through Slate plugins | Block-scoped AppKit interactions through policy and focus routing | Markfops should keep native editing primary, adopt policy-driven block operations, and avoid browser-centric interaction ownership. |
| block identity | Stable document id and heading ids only; weak general block identity | Mostly positional or content-derived | Transient source-span and offset identity | Path-based and content-derived | Durable UUID per block | Durable block identity is mandatory. SimpleBlockEditor provides the strongest structural answer; Markfops must adapt it to markdown-first editing. |
| viewport morphing feasibility | Narrow preview-only morph hook by source line; no shared scene | Weak; single DOM presentation only | Weak; no durable ids or shared geometry | Weak; no second real presentation | Moderate for single-view block continuity, but no second renderer | Future Markfops needs a viewport-scoped native coordination layer above parser and below renderers. |
| semantic transition support | Narrow heading-promotion morph in preview only | Semantic roles exist but no transition system | Semantic styling exists, no transition pipeline | Taxonomy exists, no transitions | Stable block identity across role changes, but no markdown semantics | Semantic transitions should be modeled explicitly on top of stable block ids and shared geometry snapshots, not inferred from renderer behavior. |
| scroll synchronization support | Shared `scrollRatio` baseline, but no durable block-anchor correction | Single-view assumption; no dual-view anchor ownership | Separate preview with no real sync layer | Avoids the problem with same-schema second rendering | Single-view only | Markfops needs a dual-anchor system: continuous viewport ratio plus durable semantic block anchors with drift correction. |
| memory and performance implications | Lightweight source-first state, but broad whole-document preview work | Incremental DOM updates, heavier layered state and serializer cost | Clean native ownership, but full reparse and full preview reload | Broad React plus Slate tree rendering, no viewport culling | Efficient local row reuse, but whole stack view and one text view per block | The target should keep source memory light, cache derived semantic blocks, and constrain expensive work to changed or visible blocks. |
| migration fit for Markfops | Direct baseline; preserve source-of-truth and native editor strengths | Useful only for plugin boot, parser or serializer boundaries, and commands | Strong for native source-first parse or render split | Useful only for local taxonomy and worker patterns | Strongest for durable block identity and row-scoped reuse | The target should combine Markfops baseline + Intend parse or render separation + SimpleBlockEditor identity and row ownership, while borrowing only localized ideas from Milkdown and Inkdown. |

## Cross-Reference Synthesis

### What Markfops Should Borrow

- From the baseline: markdown as the source of truth, native AppKit editing, and the existing editor or preview split as a migration-safe shell.
- From Milkdown: explicit parser or serializer boundaries, staged subsystem bootstrapping, and command registration discipline.
- From Intend: a pure parse-result boundary feeding separate renderers, source-span mapping, and editor-side patch rendering ideas.
- From Inkdown: a broad markdown block taxonomy, worker offloading for expensive transforms, and recursive serializer structure.
- From SimpleBlockEditor: durable block identity, policy-driven block editing, row-controller reuse, and explicit focus or caret routing.

### What Markfops Should Reject

- Tree-first canonical models from Milkdown and Inkdown.
- Content-derived or path-derived identity from Milkdown and Inkdown.
- Intend's passive preview and full preview reload as a long-term answer.
- SimpleBlockEditor's semantic-block-canonical model as the persisted truth.

### Minimum Viable Direction

- Keep markdown source canonical.
- Add a derived semantic block graph with durable ids and source spans.
- Feed both the native editor and preview from that derived semantic layer.
- Introduce a synchronization coordinator that owns viewport anchors, geometry snapshots, drift correction, and semantic transition scheduling.

### What Can Wait

- Full block editing as the only editing model.
- Rich multi-block selection and reordering.
- Full viewport virtualization for every block type.
- Deep plugin ecosystems comparable to Milkdown.
