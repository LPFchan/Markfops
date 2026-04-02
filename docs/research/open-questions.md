# Open Questions

- Which single richer structural pass, if any, should eventually replace the current split between `HeadingParser.parseHeadings(in:)` and `MarkdownRenderer.renderHTML(from:)` so that block identity and invalidation can stay synchronized?
- What should be the first non-heading block `identity` primitive for Markfops: source-line-based block ids, parser-owned block ids, or editor-owned layout ids?
- How far can Markfops push `NSTextView`-backed semantic attributes before it needs a parallel semantic scene model for preview and morphing?
- Which markdown constructs can reuse source-line-targeted morphing safely, and which require a different transition strategy because line numbers are not enough to preserve visual identity?
- What minimum invalidation pipeline removes full preview body replacement from the hot path while preserving markdown fidelity and memory efficiency?
- Does Markfops need a schema-level dual parse/serialize specification for semantic elements, or would that overfit a ProseMirror-style architecture that the project should avoid?
- What native identity scheme should replace content-derived heading ids if Markfops wants semantic roles to survive text edits and animate cleanly?
- What should be the primary viewport anchor for rigorous two-view scroll synchronization: source line, block identity, layout fragment identity, semantic span identity, or a hybrid?
- How should Markfops detect and correct scroll drift when editor and preview layouts diverge because of typography, code blocks, tables, images, or folded structure?
- Should Markfops standardize on a dual-anchor model of shared continuous ratio plus durable semantic block identity for all two-view synchronization work?
- Can parser/serializer separation and selection observability be reused while viewport-anchor ownership remains a native coordination subsystem outside the editor core?