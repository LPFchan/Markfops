# Agent Handoffs

## Active Handoff

- none

## Active Delta Handoffs

- none

## Pending Delta Revalidations

- none

## Completed Handoffs

- target artifact: `markfops-baseline.md`
- phase: 1
- assigned role: Markfops Baseline Subagent
- completion status: complete
- evidence standard met: yes
- completion summary:
  - `Document.rawText` is the canonical markdown source.
  - Stable identity is materially present for documents and headings, but not yet for general markdown blocks or inline spans.
  - Editor rendering is native and partially incremental; preview rendering remains whole-document HTML regeneration with body-wide DOM replacement.
  - Preview contains one narrow source-line-targeted morph hook for heading promotion, but there is no general semantic-state or shared-layout transition system yet.
- follow-on implication:
  - Phase 2 reference-repo deep dives should evaluate how external architectures could supply incremental structural state, wider block identity, and shared semantic transitions without compromising Markfops' markdown fidelity or native feel.

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
- follow-on implication:
  - The remaining reference deep dives should focus especially on native identity, native rendering ownership, and incremental semantic-state management, because Milkdown does not solve those constraints for Markfops.

- target artifact: `markfops-baseline.md`
- phase: 2 delta revalidation
- assigned role: Markfops Baseline Delta Revalidation Subagent
- completion status: complete
- evidence standard met: yes
- completion summary:
  - Current shared scroll intent is centralized in `Document.scrollRatio` and uses a viewport-center ratio in both editor and preview.
  - The current design preserves mode-switch intent well, but it cannot rigorously guarantee dual-view alignment once layout divergence or semantic block changes occur.
  - Durable non-heading block identity and drift correction are now confirmed as core missing pieces.

- target artifact: `milkdown-deep-dive.md`
- phase: 2 delta revalidation
- assigned role: Milkdown Delta Revalidation Subagent
- completion status: complete
- evidence standard met: yes
- completion summary:
  - Milkdown does not expose viewport-anchor ownership as first-class state and assumes a single ProseMirror editor view.
  - ProseMirror selection observability is useful as a change signal, but insufficient as a dual-view synchronization anchor.
  - Content-derived ids and implicit DOM scroll ownership make Milkdown a poor direct model for rigorous two-view synchronization.