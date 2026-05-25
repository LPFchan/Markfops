# RSH-20260402-004: Intend Deep Dive
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: intend-deep-dive.md

Status: completed

## Artifact Provenance

- upstream URL: https://github.com/NGA-TC-Team/intend
- checked-out branch: main
- commit SHA: f01eb8d35b533f0199afaf6908ac0f814d134373

## Scope

### Observed Facts

Intend is a native macOS markdown editor built in Swift and AppKit. The implementation inspected lives under `ref/intend/Sources/` and centers on a plain-text canonical markdown source, a pure parser that produces a `RenderNode` tree, a native `NSTextStorage`-driven editor renderer, and a separate `WKWebView` preview renderer.

The main evidence comes from:

- `Sources/Document/MarkdownDocument.swift`
- `Sources/Editor/EditorWindowController.swift`
- `Sources/Editor/MarkdownTextView.swift`
- `Sources/Editor/MarkdownTextStorage.swift`
- `Sources/Parser/MarkdownParser.swift`
- `Sources/Parser/IncrementalParser.swift`
- `Sources/Parser/RenderNode.swift`
- `Sources/Renderer/AttributeRenderer.swift`
- `Sources/Export/HTMLExporter.swift`
- `Sources/Preview/PreviewViewController.swift`
- `Sources/TOC/TOCEntry.swift`

### Architectural Interpretation

Intend is a strong native reference for source-first editing, pure parse/render separation, and AppKit ownership of the live editing surface. It is not a unified two-view engine. The editor and preview are separate products of the same parse result, not two synchronized presentations over one shared layout model.

## Topology

### Observed Facts

The repository is split into clean native modules under `Sources/`.

- `Sources/Document` owns NSDocument-backed source and encryption state.
- `Sources/Editor` owns tab/window orchestration, `MarkdownTextView`, and `MarkdownTextStorage`.
- `Sources/Parser` owns the markdown parser, incremental invalidation helpers, and `RenderNode` types.
- `Sources/Renderer` owns editor-side attribute rendering.
- `Sources/Export` owns HTML generation for preview/export.
- `Sources/Preview` owns the `WKWebView` preview panel.
- `Sources/TOC` owns heading extraction and TOC data.

The key ownership boundaries are explicit.

- `MarkdownDocument` in `Sources/Document/MarkdownDocument.swift` owns the canonical `source: String`.
- `MarkdownTextStorage` in `Sources/Editor/MarkdownTextStorage.swift` owns the backing attributed string and a cached `parseResult`.
- `PreviewViewController` in `Sources/Preview/PreviewViewController.swift` owns a `WKWebView` plus a debounced `currentMarkdown` string.
- `EditorWindowController` in `Sources/Editor/EditorWindowController.swift` wires editor callbacks to preview updates, TOC reloads, and tab orchestration.

### Architectural Interpretation

The topology is notably cleaner than a web-editor stack. Parsing, editor rendering, preview rendering, and document I/O are separate modules with narrow seams. That is highly transferable. What is less transferable is the hard split between editor and preview with no shared synchronization or identity layer between them.

## Execution Flow

### Observed Facts

Application and document flow are standard AppKit/NSDocument.

- `MarkdownDocument.read(from:ofType:)` loads or decrypts file contents into `source`.
- `MarkdownDocument.makeWindowControllers()` creates or reuses an `EditorWindowController` and adds the document as a tab.
- `EditorWindowController.addTab(document:)` creates an `EditorViewController`, loads the document text, extracts TOC entries through `extractTOCEntries(from: parse(markdown:))`, and updates the preview.

The edit path is source-first.

- User input lands in `MarkdownTextView`.
- `EditorViewController.textDidChange(_:)` reads the current editor string and triggers `onTextChange`.
- `EditorWindowController.setupCallbacks(for:)` wires `onTextChange` to `previewVC.update(markdown:)`.

The editor render path is `NSTextStorage`-driven.

- `MarkdownTextStorage.processEditing()` calls `applyAttributes()`.
- `applyAttributes()` calls `reparseIncremental(newText:editedRange:previous:)` in `Sources/Parser/IncrementalParser.swift`.
- That function currently falls back to a full `parse(markdown:)` call.
- The resulting parse tree is fed into `renderAttributes(from:config:theme:)`, and the resulting attribute patches are applied to the backing attributed string.

The preview path is full-document HTML regeneration.

- `PreviewViewController.update(markdown:)` debounces for 300 ms.
- `render()` reparses via `parse(markdown:)`, renders HTML through `renderHTML(from:config:)`, and calls `webView.loadHTMLString(...)`.

### Architectural Interpretation

The flow is clear and maintainable: edit source, parse, render native attributes, optionally regenerate preview. It is also broad in two important ways. First, parser invalidation is not truly incremental yet. Second, preview updates are always full HTML regeneration and reload.

## Data and State

### Observed Facts

The `canonical document model` is `MarkdownDocument.source: String` in `Sources/Document/MarkdownDocument.swift`.

Derived structures are transient.

- `ParseResult` in `Sources/Parser/RenderNode.swift` stores `nodes: [BlockNode]` and `sourceText: String`.
- `BlockNode` carries a `SourceSpan` with 1-based line/column coordinates.
- `MarkdownTextStorage` caches one current `parseResult`.
- `TOCEntry` in `Sources/TOC/TOCEntry.swift` derives heading title and character offset from the current parse result.

The identity model is weak.

- There is document identity through NSDocument ownership.
- Block nodes are value types recreated on each parse.
- Headings are identified in the TOC by level, plain-text title, and character offset.
- There is no durable parser-assigned id for headings, paragraphs, lists, quotes, code blocks, or inline spans.

Synchronization-relevant state is absent.

- There is no shared editor/preview viewport state object.
- There is no preview-reported scroll state in the inspected code.
- There is no explicit anchor model tying editor positions to preview DOM positions.

### Architectural Interpretation

Intend makes the classic source-first tradeoff: correctness and simplicity over persistent semantic identity. That is excellent for fidelity and maintainability. It is poor for viewport morphing and rigorous two-view scroll synchronization, because neither can be built reliably without durable identity and synchronization state layered on top of the transient parse results.

## Interaction Model

### Observed Facts

Interaction is editor-first and text-centric.

- `MarkdownTextView` handles smart editing behaviors like auto-pairing, smart Enter, and indentation.
- `EditorViewController.textDidChange(_:)` is the main edit notification path.
- TOC selection in `Sources/TOC/TOCViewController.swift` navigates by character offset back into the editor through `EditorViewController.scrollToHeading(offset:)`.
- Drag-and-drop support lands in `MarkdownTextView.performDragOperation(_:)` and opens dropped files as new tabs.

The preview is passive.

- `PreviewViewController` accepts markdown strings and renders them.
- The inspected code does not show preview-originated editing, preview-originated selection feedback, or preview scroll reporting back into the editor.

### Architectural Interpretation

This is a clean native interaction model for a markdown editor with a secondary preview pane. It is not an interaction model for synchronized dual-view editing. The absence of preview-originated state feedback means the editor remains the sole driver of user intent.

## Rendering Model

### Observed Facts

The editor renderer and preview renderer are separate codepaths sharing only the parse result shape.

- Editor-side rendering: `renderAttributes(from:config:theme:)` in `Sources/Renderer/AttributeRenderer.swift` produces `AttributePatch` values for headings, paragraphs, blockquotes, code blocks, lists, tables, horizontal rules, and inline styles.
- Preview-side rendering: `renderHTML(from:config:)` in `Sources/Export/HTMLExporter.swift` walks the same `BlockNode` tree and emits HTML.
- `PreviewViewController` loads the resulting full HTML page directly into `WKWebView`.

Current update granularity differs by presentation.

- Editor attribute application is incremental at the patch level and suppresses updates for the active editing block through `activeEditingBlockRange`.
- Parser invalidation is not yet truly incremental because `reparseIncremental(...)` still calls the full parser.
- Preview rendering is full-document regeneration and full web view reload.

`semantic transition` and scroll-sync infrastructure are absent.

- The HTML renderer does not emit durable ids or data attributes linking DOM nodes back to source spans or block identity.
- The inspected preview code does not include a JavaScript bridge for viewport reporting.
- There is no shared coordinate system or transition pipeline between the editor and preview.

### Architectural Interpretation

Intend demonstrates a viable pattern for one parse result feeding two renderers. That is transferable. It also demonstrates the limitation of that pattern when identity and synchronization are missing: two outputs of one parser do not automatically become two synchronized presentations.

## Performance Notes

### Observed Facts

Current incrementalism is partial.

- `IncrementalParser.swift` exposes `dirtyBlockRange(...)`, which shows the intended invalidation boundary strategy.
- `reparseIncremental(...)` is still a full-document parse today.
- Editor attribute application is patch-based and uses `activeEditingBlockRange` to reduce flicker and unnecessary reapplication.
- Preview updates are debounced at 300 ms but still regenerate and reload the entire HTML document.

No viewport-aware performance model is visible.

- The editor relies on AppKit text layout and overlay repositioning based on layout manager geometry.
- The preview is a passive `WKWebView` with no viewport-scoped diffing or geometry coordination.

### Architectural Interpretation

Intend prioritizes straightforward correctness over large-document scalability. Its design is likely fine for typical markdown files, but it does not yet provide the incremental parser, incremental preview updates, or viewport-aware synchronization hooks that Markfops will need for more ambitious dual-view behavior.

## Judgment

### Observed Facts

Strengths:

- Source-first canonical model in `MarkdownDocument.source`.
- Pure parser boundary through `parse(markdown:) -> ParseResult`.
- Clear separation between native attribute rendering and HTML export.
- Strong AppKit-native editing foundation.
- Dirty-block invalidation intent is already visible in code, even if not fully implemented.

Weaknesses:

- No durable block identity.
- Full-document reparse still occurs on every edit.
- Full-document preview HTML reload on every preview update.
- No viewport synchronization or preview-originated state reporting.
- No semantic transition or shared geometry infrastructure.

Copy nearly verbatim:

- `SourceSpan`-style line/column source mapping
- parse-result-to-attribute-patch rendering separation
- pure TOC extraction from parsed headings
- dirty-block-range invalidation helper shape

Generalize:

- one canonical parse entry point
- separate native and HTML renderers fed from the same parsed structure
- editor-side patch rendering and debounce strategy

Avoid:

- content-derived or offset-derived heading identity as a long-term anchor model
- full-document preview reload as a permanent solution
- keeping editor and preview as completely separate coordinate systems without a synchronization layer

Semantic transition relevance:

- Intend is useful as evidence that semantic styling can be layered on a native text editor without abandoning markdown source.
- Intend does not provide a transition model for semantic role changes.

Scroll synchronization relevance:

- Intend is mainly a negative reference here.
- It shows how a native editor plus separate web preview becomes difficult to synchronize when there is no shared viewport state, no DOM/source anchor mapping, and no preview feedback path.

### Architectural Interpretation

Intend is a valuable native reference for parser/render separation and AppKit ownership of the live editor surface. It is not a strong reference for the final Markfops dual-view architecture. The main lesson is that source-first native editing can stay clean and maintainable, but rigorous synchronization and morphing require additional layers that Intend does not yet have.

## Coordination Updates

### Recommended Completion Note for `agent-handoffs.md`

- target artifact: `intend-deep-dive.md`
- phase: 2
- assigned role: Intend Deep Dive Subagent
- completion status: complete
- evidence standard met: yes
- completion summary:
	- Intend is a native AppKit markdown editor with a plain-text canonical source and a pure parse-result pipeline feeding separate editor and preview renderers.
	- Its parser/render separation and source-span model are strong references for Markfops.
	- Its identity model is transient and source-span-based, not durable.
	- Its preview is a passive full-document HTML reload path with no scroll-sync feedback or synchronization layer.
	- It is a strong reference for native source-first editing and a weak reference for rigorous two-view synchronization.

### Recommended Updates for `open-questions.md`

- Should Markfops adopt a `SourceSpan`-style parser coordinate model for source mapping while layering durable block ids above it?
- How early should Markfops require preview-to-editor feedback channels, given that Intend's passive preview model leaves synchronization unsolved?

### Recommended Updates for `resolved-decisions.md`

- Intend confirms that a pure parse-result pipeline feeding separate native and HTML renderers is viable in a native macOS architecture.
- Intend also confirms that source-span coordinates alone are not sufficient for durable identity, semantic transitions, or rigorous two-view synchronization.
