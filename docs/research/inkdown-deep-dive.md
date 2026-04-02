# Inkdown Deep Dive

Status: completed

## Artifact Provenance

- upstream URL: https://github.com/1943time/inkdown
- checked-out branch: master
- commit SHA: 4a3666797128a30880444512699d92b84e8d1da6

## Scope

### Observed Facts

Inkdown is an Electron application built with React, Slate, MobX, and Electron-Vite rather than a native AppKit editor. This is explicit in `package.json`, `src/main/index.ts`, and the renderer-side code under `src/renderer/src/`.

The main evidence comes from:

- `package.json`
- `src/main/index.ts`
- `src/renderer/src/editor/Editor.tsx`
- `src/renderer/src/editor/elements/index.tsx`
- `src/renderer/src/editor/elements/head.tsx`
- `src/renderer/src/editor/ui/Webview.tsx`
- `src/renderer/src/store/note/note.ts`
- `src/renderer/src/store/note/output.ts`
- `src/renderer/src/store/note/import.ts`
- `src/renderer/src/store/note/worker/handle.ts`
- `src/renderer/src/store/note/worker/main.ts`
- `src/types/model.d.ts`

The repository README describes Inkdown as a WYSIWYG markdown editor plus LLM dialogue tool and marks the project as development-paused.

### Architectural Interpretation

Inkdown does not match the earlier plan assumption that it would be a compact native macOS inline-markdown specimen. It is instead a web-first, Slate-based block editor packaged in Electron. That mismatch is itself a useful finding: Inkdown is relevant as a compact schema-first block-editor specimen, not as a native text-system reference.

## Topology

### Observed Facts

The top-level structure splits into Electron main-process code, renderer/editor code, and persistence or worker infrastructure.

- `src/main/index.ts` boots Electron, initializes the database, restores windows, and registers app-level handlers.
- `src/renderer/src/editor/` owns the Slate editor, element renderers, keyboard plugins, and editor utilities.
- `src/renderer/src/store/note/` owns document and tab state, import/export, worker dispatch, and persistence coordination.
- `src/renderer/src/store/api/` owns backend-facing API wrappers.
- `src/types/model.d.ts` defines the persisted document and chat models.

Ownership boundaries are concrete.

- `IDoc.schema?: any[]` in `src/types/model.d.ts` is the canonical content payload for notes.
- `NoteStore` in `src/renderer/src/store/note/note.ts` owns the document graph, open tabs, and document-level state.
- `TabStore` owns per-tab editor state, selection-related state, search state, and editor-local caches.
- `MEditor` in `src/renderer/src/editor/Editor.tsx` owns the live Slate editing surface.
- `MarkdownOutput` in `src/renderer/src/store/note/output.ts` owns schema-to-markdown serialization.
- `WorkerHandle` in `src/renderer/src/store/note/worker/handle.ts` owns async worker dispatch for `parseMarkdown`, `toMarkdown`, `getChunks`, and `getSchemaText`.

### Architectural Interpretation

Inkdown has a clear module split and a relatively compact architecture for a feature-rich Electron editor. The important architectural fact is that the system is schema-first and Slate-centric. The editor surface is the product, and markdown is a conversion boundary rather than the authoritative model.

## Execution Flow

### Observed Facts

Startup is Electron-driven.

- `src/main/index.ts` waits for `modelReady()`, sets the app model id, restores saved windows from the database, creates a window if none were restored, and registers updater hooks.

Document load is state-store-driven.

- `NoteStore.openDoc(...)` in `src/renderer/src/store/note/note.ts` opens a note into the current or a new tab.
- `MEditor` in `src/renderer/src/editor/Editor.tsx` reacts to `tab.state.doc` changes and calls `initialNote()`.
- `initialNote()` loads `doc.schema` via `store.model.getDoc(...)` if needed and resets the editor using `EditorUtils.reset(...)`.

Edit flow is Slate-operation-driven.

- `MEditor`'s `change` callback receives the new Slate value.
- It updates `target.schema`, records selection and history in `tab.note.docStatus`, and marks the tab as changed when non-selection operations occur.
- It schedules a `tab.docChanged$` notification after 500 ms and a save after 3000 ms.

Persistence and export are asynchronous.

- `save()` in `Editor.tsx` gathers wiki-link and media references, writes the updated schema into `NoteStore`, and then asynchronously persists through `store.local.writeDoc(...)` and `store.model.updateDoc(...)`.
- `WorkerHandle.toMarkdown(...)` and `MarkdownOutput` convert the canonical schema back into markdown.
- `WorkerHandle.parseMarkdown(...)` dispatches markdown parsing to the worker when importing or inserting markdown-derived content.

### Architectural Interpretation

This is a standard schema-editor pipeline: load schema, mutate schema through editor operations, debounce, then persist schema and optionally derive markdown. The flow is efficient for a rich block editor, but it inverts Markfops' markdown-first constraint and leaves little room for treating markdown text as the canonical state boundary.

## Data and State

### Observed Facts

`canonical document model` is `IDoc.schema` in `src/types/model.d.ts`.

- Documents have durable note-level identity via `IDoc.id`.
- Content is stored as a Slate-style node array in `schema`.
- `NoteStore.state.nodes` owns the in-memory document graph.
- `NoteStore.docStatus` stores per-document history and selection snapshots.
- `TabStore` owns per-tab caches such as search ranges, code editor instances, and other editor-local state.

The block identity model is transient.

- Slate operations address content by tree position and path.
- No durable block identifier is visible in the inspected block nodes.
- Renderer code such as `elements/head.tsx` emits DOM data attributes like `data-head` derived from `slugify(Node.string(element))`, which is content-derived and not durable under edits.

Reference identity exists for some non-block objects.

- Wiki links can carry `docId`.
- Media nodes can carry `id`.

### Architectural Interpretation

Inkdown has durable identity at the document and asset level, but not at the semantic block level. That makes it unsuitable as a direct reference for viewport morphing, persistent cross-view anchors, or rigorous synchronization. The content-derived heading slug is useful for local navigation, not for long-lived semantic identity.

## Interaction Model

### Observed Facts

The main interaction surface is the live Slate editor in `src/renderer/src/editor/Editor.tsx`.

- Keyboard behavior is plugin-driven under `src/renderer/src/editor/plugins/`.
- Paste handling can convert HTML to markdown via `htmlToMarkdown(...)` and route that through editor insertion logic.
- File drops call `insertMultipleImages(...)`.
- Link interactions in `src/renderer/src/editor/elements/index.tsx` support opening URLs and internal docs.
- Internal heading links use the content-derived `data-head` attribute and `tab.container?.scroll({ top, behavior: 'smooth' })`.

Inkdown also has a read-only secondary renderer, but it is not a separate semantic preview system.

- `src/renderer/src/editor/ui/Webview.tsx` creates a fresh Store, opens a doc, resets a read-only Slate editor with the existing schema, and renders the same element components through `<Editable readOnly={true} />`.

### Architectural Interpretation

This is still a single-model editor architecture. The so-called webview is effectively another Slate rendering of the same schema, not an independently rendered markdown preview with its own layout model. That matters because it avoids one class of synchronization problems only by never creating the dual-renderer problem Markfops is trying to solve.

## Rendering Model

### Observed Facts

Rendering is a direct Slate-node-to-React-component mapping.

- `MElement` in `src/renderer/src/editor/elements/index.tsx` switches on `element.type` and returns components like `Head`, `Paragraph`, `Blockquote`, `List`, `AceElement`, `Table`, `Media`, and `WikiLink`.
- `MLeaf` maps inline marks such as `bold`, `italic`, `code`, `strikethrough`, `url`, `docId`, and highlight flags into styled inline spans.
- `Head` in `src/renderer/src/editor/elements/head.tsx` renders semantic heading tags and attaches `data-head` based on slugified heading text.

Markdown serialization is separate.

- `MarkdownOutput.parserNode(...)` in `src/renderer/src/store/note/output.ts` recursively walks schema nodes and emits markdown syntax.
- `WorkerHandle` dispatches parse and export work to the worker.

There is no native preview renderer and no HTML-preview coordination layer in the inspected path.

- The read-only `Webview.tsx` path renders Slate again.
- Search and syntax highlighting are decorator and leaf-mark based rather than projection into a separate preview domain.

### Architectural Interpretation

The rendering model is simple and economical for a single editor tree. It is not designed for dual-presentation coordination, semantic transitions between editor and preview, or any shared geometry system. Its strongest transferable idea is the clean separation between schema serialization and element rendering, not the rendering topology itself.

## Performance Notes

### Observed Facts

Inkdown has some async and debounce discipline.

- Heavy markdown parsing and export work is pushed into a worker via `WorkerHandle` and msgpack-encoded messages.
- Content changes debounce lightweight notifications at 500 ms and persistence at 3000 ms.

Current rendering remains broad.

- The editor renders the whole Slate document tree in React.
- The inspected code does not show viewport virtualization or a block-geometry cache for visible-only updates.
- Search highlighting, syntax-related decoration, and code-block integration add more editor-local rendering work on top of the full document view.

### Architectural Interpretation

Inkdown is plausibly efficient enough for many ordinary notes, but it is not built around viewport-scoped rendering guarantees. For Markfops' future morphing and synchronization requirements, that is a meaningful limitation: a whole-document React plus Slate rendering pipeline does not naturally provide the geometry ownership or frame-budget control needed for native-feeling viewport transitions.

## Judgment

### Observed Facts

Strengths:

- Clear block taxonomy covering paragraphs, headings, quotes, lists, code, tables, media, and wiki links.
- Compact schema-first persistence model.
- Explicit async worker boundary for markdown parsing and export.
- Clean recursive schema-to-markdown serializer shape in `MarkdownOutput`.
- Durable note-level identity via `IDoc.id` and durable asset or link references via `id` and `docId`.

Weaknesses:

- Electron and web-stack foundation rather than native AppKit ownership.
- Canonical model is schema, not markdown text.
- No durable semantic block identity.
- No true dual-renderer editor/preview architecture.
- No viewport-scoped rendering strategy or transition system.

Copy nearly verbatim:

- broad markdown block taxonomy for headings, paragraphs, quotes, lists, code, tables, media, and wiki links
- recursive switch-over-node-type structure for schema-to-markdown output
- async worker boundary for heavyweight markdown import or export work
- explicit `docId` and media `id` reference fields instead of raw embedded cross-document payloads

Generalize:

- keep parsing and markdown export off the interactive UI path
- separate element rendering concerns from serialization concerns
- use content-only save debounce rather than persisting on every selection change
- treat heading slug attributes as local navigation affordances, not durable identity

Avoid:

- schema-as-canonical design where markdown becomes peripheral
- path-based or content-derived block identity for any long-lived coordination need
- assuming a read-only second Slate tree is equivalent to a real preview architecture
- whole-document rendering as the long-term basis for viewport-sensitive transitions
- deriving semantic block identity from heading text slugs

Semantic transition relevance:

- Inkdown has almost no direct value here.
- It demonstrates a clean semantic element taxonomy, but not a semantic transition system.
- Markfops can reuse the taxonomy ideas while designing transitions elsewhere.

Scroll synchronization relevance:

- Inkdown is not a useful direct reference for rigorous two-view synchronization.
- It avoids the problem by remaining effectively single-model and single-render-topology.
- The read-only Slate `Webview` does not provide evidence for independent preview anchoring, cross-render drift correction, or preview-owned scroll feedback.

### Architectural Interpretation

Inkdown is best treated as a compact web-first block-editor specimen. Its value to Markfops is local: block taxonomy, worker boundaries, serializer structure, and some reference-field patterns. It should not shape the target architecture for native editing, markdown-first ownership, semantic transitions, or synchronized dual presentations.