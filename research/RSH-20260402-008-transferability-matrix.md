# RSH-20260402-008: Transferability Matrix
Opened: 2026-04-02 19-19-39 KST
Recorded by agent: codex-markfops-repo-template-migration-20260409
Migrated from legacy file: transferability-matrix.md

Status: completed

## Copy Nearly Verbatim

| Idea | Source | Why It Transfers Cleanly | Markfops Adoption Note |
| --- | --- | --- | --- |
| Durable UUID-based block identity | SimpleBlockEditor | Local, native, architecture-agnostic, and essential for cross-presentation continuity | Add stable ids to derived semantic blocks while keeping markdown source canonical. |
| Policy/context split for structural editing | SimpleBlockEditor | Editing intent stays separate from mutation mechanics | Use policy objects for semantic block operations such as split, merge, promote, demote, and list continuation. |
| Row-controller reuse keyed by block id | SimpleBlockEditor | Directly supports incremental native row updates | Apply to editor-side block overlays, block presenters, or hybrid row wrappers. |
| Pure TOC extraction from parsed headings | Intend | Small, clear, and source-first | Keep heading extraction as a derived service over parsed semantic blocks. |
| Recursive serializer walk by node type | Inkdown | Straightforward and testable | Use for markdown regeneration from derived semantic blocks when structural editing is introduced. |
| Dirty-block-range invalidation helper shape | Intend | Good local pattern even though Intend's current implementation is incomplete | Use block-local invalidation planning around source spans and durable block ids. |
| Source-span line or column mapping | Intend | Strong bridge between markdown text and semantic blocks | Keep source spans on every derived semantic block and inline range where feasible. |
| Command and keymap registration discipline | Milkdown | Local design pattern, not tied to ProseMirror if abstracted | Centralize command registration instead of scattering keyboard logic across views. |

## Generalize

| Idea | Source | What Is Valuable | How Markfops Should Adapt It |
| --- | --- | --- | --- |
| Parser/serializer subsystem boundaries | Milkdown, Intend | Keep transforms distinct from presentation and commands | Implement native services over markdown source and semantic blocks rather than over ProseMirror state. |
| Separate native and HTML renderers fed by shared parsed structure | Intend | One semantic layer, two renderers | Feed editor and preview from a shared semantic scene with durable ids and geometry hooks. |
| Worker offloading for expensive transforms | Inkdown | Keep heavyweight parsing or export off the interaction path | Use background queues for preview HTML generation, diff planning, and non-visible block work. |
| Broad markdown block taxonomy | Inkdown | Useful coverage vocabulary for block kinds and semantics | Normalize block taxonomy for Markfops while preserving markdown-first storage. |
| Slice-style subsystem bootstrapping | Milkdown | Explicit initialization dependencies reduce accidental coupling | Use a smaller native coordinator graph for parser, identity, renderers, sync, and animation subsystems. |
| Editor-side patch rendering | Intend | Avoid full attributed-string restyles when only local regions changed | Apply incremental style updates to visible editor regions keyed by semantic block changes. |
| Event-queue observation rather than broad direct state observation | SimpleBlockEditor | Narrow invalidation and explicit update semantics | Use event streams for semantic block updates, geometry changes, and sync-anchor changes. |
| Local heading slug anchors for navigation | Inkdown, Markfops baseline | Useful as human-readable DOM anchors | Treat as navigational affordances only, never as durable semantic identity. |

## Avoid

| Idea | Source | Why It Should Be Rejected | Markfops Consequence |
| --- | --- | --- | --- |
| Tree-first canonical state | Milkdown, Inkdown, SimpleBlockEditor | Breaks markdown-first fidelity and complicates trustworthy round-trip editing | Keep markdown source canonical and derive all richer structure. |
| Content-derived heading ids | Milkdown, Inkdown | Unstable under text edits and unsuitable for morphing or sync anchors | Use durable ids generated independently from content. |
| Path-based identity | Inkdown | Breaks under structural edits and cannot anchor long-lived transitions | Never use tree position as durable identity. |
| Full-document preview reload as steady-state behavior | Intend, current Markfops baseline | Too broad for synchronized dual-view behavior and smooth viewport transitions | Move toward block-scoped preview diffing or targeted DOM patching. |
| Browser-DOM-centric core editor architecture | Milkdown, Inkdown | Conflicts with native-feel and AppKit-first constraints | Keep native editor ownership in AppKit or TextKit. |
| Assuming a read-only second editor tree is a preview architecture | Inkdown | Dodges rather than solves dual-renderer coordination | Build a true preview projection with separate semantics and explicit synchronization ownership. |
| Semantic blocks as persisted truth | SimpleBlockEditor | Excellent for block editing, poor for markdown fidelity if used directly as storage | Use semantic blocks as derived state only. |
| Passive preview with no feedback channel | Intend | Leaves synchronization and drift correction unsolved | Add preview-to-coordinator anchor reporting early in the architecture. |
