# RSH-20260402-002: Markfops Baseline Architecture
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: markfops-baseline.md

Status: completed

## Scope

### Observed Facts

This baseline covers the current Markfops implementation under `Markfops/` only. The evidence comes from the native app entry points in `Markfops/App`, state ownership in `Markfops/State`, editing infrastructure in `Markfops/Editor`, parsing in `Markfops/Parsing`, markdown rendering in `Markfops/Renderer`, presentation logic in `Markfops/Views`, command dispatch in `Markfops/Commands`, and PDF export in `Markfops/FileIO`.

The current product is a native macOS markdown editor with two primary presentations over one canonical markdown document: an AppKit `NSTextView` editor and a WebKit preview. The canonical markdown source lives in `Markfops/State/Document.swift` as `Document.rawText`.

### Architectural Interpretation

The current architecture already preserves several Markfops constraints well: native feel on the editing side, markdown fidelity via a plain-text source of truth, and a clean separation between state, parsing, rendering, and presentation. The main Phase 1 question is not whether Markfops has a viable baseline. It does. The question is where its current whole-document recomputation and split editor/preview identity model will block incremental native WYSIWYG migration.

## Topology

### Observed Facts

The app is organized into a small number of clear subsystems.

- Application entry and window bootstrapping live in `Markfops/App/MarkfopsApp.swift` and `Markfops/App/AppDelegate.swift`.
- Canonical document and multi-tab ownership live in `Markfops/State/Document.swift` and `Markfops/State/DocumentStore.swift`.
- Editor presentation lives in `Markfops/Editor/MarkdownEditorView.swift` and `Markfops/Editor/TextViewCoordinator.swift`.
- Markdown syntax coloring lives in `Markfops/Editor/MarkdownSyntaxHighlighter.swift`.
- Heading extraction lives in `Markfops/Parsing/HeadingParser.swift`.
- Markdown-to-HTML conversion and preview page assembly live in `Markfops/Renderer/MarkdownRenderer.swift` and `Markfops/Renderer/HTMLTemplate.swift`.
- SwiftUI composition and mode switching live in `Markfops/Views/ContentView.swift`, `Markfops/Views/EditorContainerView.swift`, `Markfops/Views/PreviewView.swift`, and `Markfops/Views/SidebarView.swift`.
- Menu and keyboard command routing live in `Markfops/Commands/MarkfopsCommands.swift`.
- HTML-to-PDF export lives in `Markfops/FileIO/PDFExporter.swift`.

The ownership boundary is straightforward:

- `DocumentStore.documents` owns the open-document set.
- `DocumentStore.activeID` owns the active tab selection.
- Each `Document` owns the canonical document model and document-scoped UI state.
- `EditorContainerView` chooses which presentation layer is active based on `Document.mode`.
- `PreviewBridge` and `EditorBridge` are adapter surfaces that let SwiftUI drive AppKit and WebKit coordinators without moving ownership out of `Document`.

### Architectural Interpretation

The topology is already good enough for incremental migration if new structure is inserted between `Document.rawText` and the current editor/preview presentations instead of bypassing them. The current module split is more of an asset than a liability. The main weakness is not coarse file organization. It is that `rawText` fans out into multiple derived structures without a shared incremental scene or semantic-state layer.

## Execution Flow

### Observed Facts

App startup and document bootstrapping are native and direct.

- `MarkfopsApp` creates the application scene and injects a `DocumentStore` into the SwiftUI environment.
- `DocumentStore.newDocument()` creates a new `Document`, registers observation, appends it to `documents`, and makes it active.
- `DocumentStore.open(url:)` reads UTF-8 text from disk, creates `Document(fileURL:rawText:)`, populates `Document.headings` with `HeadingParser.parseHeadings(in:)`, appends the document, sets it active, and calls `Document.startWatching()`.

The edit path is centered on AppKit text editing.

- `EditorContainerView` selects `EditorView` when `Document.mode == .edit`.
- `EditorView` creates a `MarkdownNSTextView` and connects it to `TextViewCoordinator`.
- `TextViewCoordinator.textDidChange(_:)` is the main mutation path for source edits. It reads `textView.string`, writes the new value into `Document.rawText`, calls `Document.updateTextMetrics()`, and updates `Document.isDirty` against `Document.savedText`.
- The same delegate schedules a debounced heading refresh by calling `HeadingParser.parseHeadings(in:)` on a background queue and writing the result back into `Document.headings` on the main queue.

The preview path is full-document markdown rendering.

- `EditorContainerView.refreshPreview(from:)` calls `MarkdownRenderer.renderHTML(from:)` and then `HTMLTemplate.currentPage(body:colorScheme:)`.
- `MarkdownRenderer.renderHTML(from:)` uses `libcmark_gfm` with `CMARK_OPT_SOURCEPOS`, renders a full HTML fragment, injects source-line attributes, and injects heading DOM ids.
- `PreviewView.updateNSView(_:context:)` either does a full `WKWebView.loadHTMLString` on first load or theme changes, or performs a body-level HTML replacement through `PreviewView.Coordinator.updateBodyHTML(_:)`.

Mode switching is orchestrated in one place.

- `EditorContainerView.onChange(of: document.mode)` restores editor scroll from `Document.scrollRatio` when returning to edit mode.
- The same change handler calls `bridge.setPendingScrollRatio(document.scrollRatio)` and `refreshPreview(from: document.rawText)` when entering preview mode.

Persistence and external reload are source-centric.

- `DocumentStore.save(_:)` writes `Document.rawText` to disk, updates `savedText`, clears `isDirty`, and restarts file watching.
- `Document.reloadFromDiskIfClean(restartWatching:)` only reloads external file changes when `isDirty == false`, then updates `rawText`, line metrics, `savedText`, headings, and active heading state.
- `DocumentStore.exportAsPDF(_:)` renders fresh HTML from `Document.rawText`, wraps it in the current template, and hands the result to `PDFExporter`.

Command dispatch follows focused state and bridge objects.

- `MarkfopsCommands` pulls `DocumentStore`, `FindController`, and `PreviewBridge` from focused values.
- File commands call `DocumentStore` methods directly.
- Format commands route to `MarkdownNSTextView` selectors for bold, italic, inline code, and heading application.
- Preview-side heading promotion uses `PreviewBridge.promoteSelectionToHeading(_:in:)`, which ultimately calls `PreviewView.Coordinator.promoteSelectionToHeading(_:in:)` and then mutates `Document.rawText` with `MarkdownHeadingFormatter.applyHeading(level:to:sourceLine:)`.

### Architectural Interpretation

Control flow is easy to trace because there are few hidden ownership transfers. The important architectural consequence is that nearly every meaningful update still funnels through full-document text mutation or full-document derived-state recomputation. The code is understandable, but the invalidation model is broad.

## Data and State

### Observed Facts

The `canonical document model` is `Document.rawText` in `Markfops/State/Document.swift`.

Document-owned state includes:

- `Document.id`: stable UUID for document identity.
- `Document.fileURL`: persisted file location.
- `Document.rawText`: canonical markdown source.
- `Document.savedText`: last clean saved or opened source.
- `Document.isDirty`: clean/dirty flag.
- `Document.mode`: `.edit` or `.preview`.
- `Document.lineCount`: derived line metric.
- `Document.headings`: derived heading structure.
- `Document.activeHeadingID`: currently focused TOC identity.
- `Document.scrollRatio`: viewport-center position, marked `@ObservationIgnored` to avoid broad SwiftUI invalidation on scroll.
- `Document.isTOCExpanded` and `Document.collapsedHeadingIDs`: TOC presentation state.
- `Document.fileWatchSource`: kqueue-based file watcher.

The primary `derived structure` today is heading metadata.

- `HeadingParser.parseHeadings(in:)` returns `[HeadingNode]` where each node stores `level`, `title`, and `lineNumber`.
- `HeadingNode.id` is `"\(lineNumber)-\(level)-\(title)"` for SwiftUI identity.
- `HeadingNode.domID` is `"markfops-heading-\(lineNumber)-\(level)"` for preview navigation.

Other derived structures are preview-specific.

- `MarkdownRenderer.renderHTML(from:)` produces an HTML fragment from `rawText`.
- `MarkdownRenderer.injectSourceLineAttributes(into:)` adds `data-markfops-source-line` attributes.
- `MarkdownRenderer.injectHeadingIDs(into:using:)` maps headings back onto rendered `<h1>` through `<h6>` tags.
- `EditorContainerView` stores the full page HTML in `htmlContent` and the HTML fragment in `bodyHTML`.
- `PreviewView.Coordinator` caches `lastThemeKey`, `lastRenderedBodyHTML`, `pendingScrollRatio`, `pendingHeading`, and `pendingMorphSourceLine`.

State ownership by subsystem is explicit.

- The editor owns AppKit selection state, undo stack, and incremental syntax highlighting state.
- The preview owns DOM state and preview-local scroll position behavior inside `WKWebView`.
- The sidebar reads `Document.headings` and `Document.activeHeadingID`; it does not own structural data.

Current `identity` support exists, but only partially.

- Document identity is stable through `Document.id`.
- Heading identity is stable enough for TOC selection and preview anchor navigation through `HeadingNode.id` and `HeadingNode.domID`.
- Source-line attributes in preview provide a weak bridge from rendered HTML back to source lines.
- There is no shared native identity for arbitrary paragraphs, lists, quotes, code blocks, or inline spans across editor and preview.

### Architectural Interpretation

The source-of-truth story is strong: markdown fidelity is protected because every meaningful projection can be thrown away and regenerated from `rawText`. The weak point is the gap between the canonical text model and the richer semantic identity a morphing WYSIWYG engine will need. Today Markfops has heading identity, not general block identity, and it has DOM source-line tagging, not a durable cross-mode scene graph.

## Interaction Model

### Observed Facts

Editing behavior is anchored in `MarkdownNSTextView` and `TextViewCoordinator`.

- `MarkdownNSTextView.performKeyEquivalent(with:)` intercepts Command-B and Command-I for markdown wrapper insertion.
- `MarkdownNSTextView.applyHeading(level:)` uses `MarkdownHeadingFormatter.applyHeading(level:to:selection:)` and currently replaces the full document string through `replaceCharacters(in:with:)` over the full range.
- `TextViewCoordinator.find(_:forward:)`, `replaceCurrentMatch(find:replace:)`, and `replaceAll(find:replace:)` implement editor find/replace with direct `NSString` range search and AppKit selection updates.

Preview behavior is mostly read-only, with one narrow source-mutation path.

- `PreviewView` renders HTML inside `WKWebView`.
- `PreviewView.Coordinator.find(_:forward:completion:)` uses JavaScript search over the preview DOM.
- `PreviewView.Coordinator.scrollToHeading(_:)` animates preview jumps to heading anchors.
- `PreviewView.Coordinator.promoteSelectionToHeading(_:in:)` extracts a source line from the selected DOM block, then mutates `Document.rawText` through `MarkdownHeadingFormatter` and refreshes headings. This is not general in-preview rich editing. It is a targeted command that still round-trips through the markdown source.

Scrolling is coordinated through viewport-center ratios.

- `TextViewCoordinator.scrollViewDidLiveScroll(_:)` computes `Document.scrollRatio` from the center of the visible editor viewport and then calls `Document.syncActiveHeadingToScrollPosition()`.
- `PreviewView` posts throttled scroll ratios from JavaScript back to Swift, and `EditorContainerView` writes those ratios into the same `Document.scrollRatio`.

Sidebar and tab interactions operate through document-level state.

- TOC selection uses `HeadingNode` values and `HeadingNode.id`.
- Active-heading highlighting is derived from `Document.activeHeadingID`.
- Tab ownership and detachment stay in `DocumentStore` and `TabDragState`.

### Architectural Interpretation

Markfops already behaves like a native text editor first and a preview second. That is good for native feel and markdown safety. The downside is that interaction semantics are attached to either AppKit text ranges or preview DOM nodes, depending on mode, with no shared higher-level interaction object between them. The preview-side heading promotion code shows that the product is already probing semantic transitions, but only through narrow bridge logic.

## Rendering Model

### Observed Facts

The editor rendering path is incremental only at the syntax-coloring level.

- `MarkdownSyntaxHighlighter.textStorage(_:didProcessEditing:range:changeInLength:)` expands the edited range to full lines and recolors only those lines.
- `MarkdownSyntaxHighlighter.highlight(textStorage:in:)` applies regex-based styling for headings, emphasis, code, blockquotes, links, lists, task lists, and rules.
- Syntax markers remain visible; Markfops does not currently hide source syntax in the editor.

Heading parsing is line-based and whole-document.

- `HeadingParser.parseHeadings(in:)` scans every line, toggles fence state for fenced code blocks, accepts ATX headings, and ignores headings inside fences.
- The parser does not build a full markdown AST and does not cover setext headings.

Preview rendering is whole-document markdown-to-HTML.

- `MarkdownRenderer.renderHTML(from:)` fully reparses markdown through `libcmark_gfm` on each preview refresh.
- The renderer then performs a second heading extraction pass through `HeadingParser.parseHeadings(in:)` inside `injectHeadingIDs(into:using:)`.
- `HTMLTemplate.currentPage(body:colorScheme:)` wraps the fragment in a complete page with inlined CSS.

Preview DOM updates are body-wide, not subtree-diffed.

- `PreviewView.updateNSView(_:context:)` caches the last body HTML string and theme key.
- If only the body changes, `PreviewView.Coordinator.updateBodyHTML(_:)` calls a JavaScript helper that replaces `article.innerHTML` wholesale.

There is a limited preview-local `semantic transition` hook.

- `PreviewView.Coordinator.pendingMorphSourceLine` stores a source line for a targeted post-update morph.
- The injected `window.__markfopsPreview.applyHTML(nextHTML, sourceLine)` snapshots block styles before HTML replacement, swaps the body HTML, restores scroll based on viewport-center ratio, and calls `animateBlockMorph` on the updated block matching `data-markfops-source-line`.
- This gives Markfops a preview-only block-style morph for targeted heading promotion, but not a general semantic-state system or cross-mode transition model.

### Architectural Interpretation

The rendering architecture cleanly separates editor rendering from preview rendering, but it also splits them so hard that there is no shared layout or semantic state across modes. The current preview morph hook is useful evidence: Markfops can already animate a small class of semantic presentation change when it can preserve source-line targeting through a refresh. That is promising, but it is still a local DOM trick layered on top of full HTML replacement. It is not yet the stable-identity viewport morphing pipeline described in the research plan.

## Performance Notes

### Observed Facts

Current incremental work is narrow.

- Editor syntax highlighting is line-scoped.
- AppKit text layout remains incremental through `NSTextView` and its layout machinery.
- Scroll ratio updates are O(1) per event and avoid broad observation churn because `Document.scrollRatio` is `@ObservationIgnored`.

Current broad recomputation points are easy to identify.

- `TextViewCoordinator.textDidChange(_:)` triggers a full heading reparse after a 500 ms debounce.
- `EditorContainerView.refreshPreview(from:)` triggers a full markdown-to-HTML render for preview refresh.
- `MarkdownRenderer.injectHeadingIDs(into:using:)` reparses headings again during preview generation.
- `PreviewView.Coordinator.updateBodyHTML(_:)` replaces the full preview article body, not just changed blocks.
- `MarkdownNSTextView.applyHeading(level:)` replaces the full editor text buffer even when only one line changes.

Current memory behavior is conservative but coarse.

- The canonical markdown model is one `String` per document.
- Preview HTML is cached as strings in SwiftUI state plus DOM state inside `WKWebView`.
- Heading metadata is rebuilt as fresh arrays.
- There is no persistent AST cache, block cache, or reusable semantic scene tree.

### Architectural Interpretation

The current design is likely fine for ordinary markdown documents and explains why Markfops feels lightweight today. It is not yet prepared for native WYSIWYG semantics at scale because the expensive work is aligned with the whole document, not the visible viewport or changed semantic region. The biggest transition blockers are not the native editor path. They are the full preview rerender path, duplicated heading extraction, and lack of reusable block identity below the heading level.

## Judgment

### Observed Facts

Strengths backed by the codebase:

- `Document.rawText` in `Markfops/State/Document.swift` is an unambiguous source of truth.
- `DocumentStore` keeps lifecycle, save/open, rename, duplicate, close, and detach behavior centralized.
- `MarkdownNSTextView` keeps editing native and leverages AppKit undo, selection, and layout.
- `TextViewCoordinator` cleanly isolates editor mutation, heading refresh, search, and scroll sync.
- `MarkdownRenderer` and `HTMLTemplate` isolate preview generation cleanly.
- `HeadingNode.domID` and source-line attributes give the preview a concrete identity bridge for headings and some source-line-targeted updates.

Weaknesses backed by the codebase:

- Whole-document preview regeneration remains the default path.
- Heading extraction is duplicated between the document update path and the preview rendering path.
- Stable identity below headings is largely absent.
- Editor and preview maintain separate layout engines and separate selection models.
- Preview-local morphing exists only as a narrow DOM-side effect and cannot support full cross-mode object continuity.

### Architectural Interpretation

What Markfops should preserve:

- markdown as canonical source
- native AppKit editing as the interaction baseline
- viewport-center scroll continuity
- clear state ownership in `Document` and `DocumentStore`

What Markfops should treat as migration pressure:

- whole-document render invalidation
- duplicated structural parsing
- lack of general block identity
- separation between editor layout and preview layout with no shared semantic scene

What this baseline implies for later phases:

- A viable target architecture should remain source-first and native-first.
- New semantic layers should sit between `rawText` and presentation, not replace markdown with rendered state.
- Early WYSIWYG migration should target incremental block identity and semantic state before ambitious full Notion-like block composition.
- Web-specific tricks in the preview can inform behavior, but they should not dominate the target architecture.

## Scroll Synchronization Delta Revalidation

### Observed Facts

The current shared scroll-state owner is `Document.scrollRatio` in `Markfops/State/Document.swift`. Both presentations write into that same field.

- Editor path: `TextViewCoordinator.scrollViewDidLiveScroll(_:)` in `Markfops/Editor/TextViewCoordinator.swift` computes a viewport-center ratio from the visible AppKit viewport and writes it into `document.scrollRatio`.
- Preview path: the JavaScript scroll handler in `Markfops/Views/PreviewView.swift` computes the same center-of-viewport ratio, posts it through `scrollChanged`, and the coordinator writes it back into the same `Document`.

The current anchor model is a viewport-center ratio, not a top-edge pixel offset.

- Editor restoration uses `scrollToRatio(_:)` in `Markfops/Editor/TextViewCoordinator.swift`, reconstructing `targetY` from `ratio * totalHeight - visibleHeight / 2`.
- Preview restoration uses the same center-of-viewport formula in `PreviewBridge.setPendingScrollRatio(_:)` and `PreviewView.Coordinator.webView(_:didFinish:)`.

Mode-switch restoration is already explicit.

- `Markfops/Views/EditorContainerView.swift` restores preview-to-editor position through `editorBridge.scrollToRatio(document.scrollRatio)`.
- The same file restores editor-to-preview position by queueing `bridge.setPendingScrollRatio(document.scrollRatio)` before preview load or refresh.

Current code already exposes partial semantic anchors for sync.

- `MarkdownRenderer.injectSourceLineAttributes(into:)` in `Markfops/Renderer/MarkdownRenderer.swift` adds `data-markfops-source-line` to rendered blocks.
- Headings have stronger identity through `HeadingNode.id` and `HeadingNode.domID` in `Markfops/State/HeadingNode.swift`.
- Preview-side semantic morphing already captures a targeted source line through `pendingMorphSourceLine` in `Markfops/Views/PreviewView.swift`.

Current drift risks are concrete.

- Editor and preview use different layout engines and different typography stacks.
- Preview replaces `article.innerHTML` wholesale during updates, invalidating prior DOM geometry.
- Non-heading blocks do not yet have durable identity beyond source-line correlation.
- Ratio restoration does not validate that the same semantic block remains centered after relayout.

### Architectural Interpretation

The current design gets one important thing right: a single shared scroll-intent value already exists, and viewport-center anchoring is the correct baseline because it is more perceptually stable than top-edge anchoring when the two presentations differ modestly.

What it cannot guarantee yet is rigorous two-view synchronization. A pure ratio anchor is necessary but not sufficient. The future engine needs a hybrid anchor model: shared continuous intent through ratio plus validation and correction through stable block identity.

That means the next architecture should preserve `Document.scrollRatio` or an equivalent shared intent channel, but add:

- stable identity for non-heading blocks
- a way to resolve the currently centered semantic block in both presentations
- drift detection after relayout or semantic change
- corrective re-anchoring when ratio alone lands on the wrong content

The preview-side `pendingMorphSourceLine` flow is the proof-of-concept for this direction. It shows that once the system knows which semantic block changed, it can preserve intent and animate intelligently. The missing piece is generalizing that beyond headings and source lines into a durable dual-view anchor system.

## Open Questions

- Should heading extraction remain a standalone line parser, or should Markfops move to one richer incremental structure pass that can also feed preview identity and future block semantics?
- Where should general block `identity` live for paragraphs, lists, quotes, and code blocks so it survives editor updates and preview refreshes?
- Can `NSTextView`-backed editing carry enough semantic attributes for the first native WYSIWYG stages, or does Markfops need a parallel semantic model before richer inline hiding and block transitions begin?
- Which markdown constructs can reuse the preview-side source-line morph idea, and which ones require a different cross-mode layout strategy?
- What is the smallest incremental invalidation model that removes whole-document preview recomputation from the critical path without compromising markdown fidelity?
- What is the minimum stable non-heading block identity scheme that can survive source edits and semantic transitions while still mapping cleanly back to markdown text?
- Should rigorous two-view sync use a dual anchor model of `scrollRatio + block identity`, or does Markfops need an even stronger layout-fragment anchor for some constructs?
- Should scroll drift correction be reactive after relayout, predictive before transition, or hybrid?

## Resolved Decisions

- The current `canonical document model` is `Document.rawText`; all other structures are derived and disposable.
- The current heading identity strategy is source-line-based through `HeadingNode.id` and `HeadingNode.domID`.
- Preview interaction remains source-first: even the preview-side heading promotion path mutates markdown source rather than treating rendered HTML as authoritative state.
- The baseline confirms that Markfops already has one narrow semantic-transition prototype in preview (`pendingMorphSourceLine` plus `window.__markfopsPreview.applyHTML`), but it does not yet have a general semantic-state or shared-layout architecture.
- Phase 2 should compare external references against this baseline instead of against generic editor goals.
- The current viewport-center ratio anchor is the correct baseline for shared scroll intent and should be preserved.
- Rigorous two-view synchronization will require block-identity validation and correction layered on top of that ratio baseline.
