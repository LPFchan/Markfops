# DEC-20260909-001: The Reader View Becomes Native Text
Opened: 2026-09-09 17-17-39 KST
Recorded by agent: claude-torph-spike-20260909

## Metadata

- Status: accepted
- Deciders: operator
- Scope: engine architecture; refines `DEC-20260409-003`
- Related ids: `RSH-20260909-001`, `RSH-20260402-011`, `RSH-20260402-012`, `RSH-20260402-013`

## Decision

The reader view converts from a `WKWebView` rendering of generated HTML to a native TextKit presentation of the same text the editor holds. Editor and reader become two stylings of one native text engine. The web preview is kept only until the native reader covers what users rely on, and afterwards only for jobs where HTML is the right tool, such as export and printing.

## Context

Markfops has a native editor and a web-page reader. The April research (`RSH-20260402-011` through `013`) framed cross-view motion and scroll synchronization as coordination problems between two layout engines and stalled on them. `RSH-20260909-001` showed that torph-style morphing works natively when both presentations report glyph positions from TextKit, and that the reader side was the only part it had to fake.

## Options Considered

- Keep the web reader and build synchronization and transition coordinators that bridge the two engines
- Make the reader native and let both presentations share one text engine
- Make the editor web-based as well

## Rationale

Every hard problem in the risk register traces back to the two-engine split: geometry that cannot be read in the same frame, a process boundary for every measurement, and scroll drift between layouts that do not agree. A native reader removes the split instead of bridging it. The native WYSIWYG goal already requires rendering Markdown semantics in native text, so keeping a web reader alongside means building the same rendering twice. A web editor contradicts the product thesis in `SPEC.md`.

## Consequences

- Synchronization between editor and reader is no longer a coordinator between engines. Both presentations share storage and layout, so scroll anchors are the same text positions.
- The Transition Coordinator idea from `DEC-20260409-003` survives in reduced form: measure positions in both stylings, pair characters through parser source spans, and animate with Core Animation.
- Durable semantic identity is still required, but the first version is a per-character kind map derived from the existing cmark-gfm node positions, not a new parse service.
- Tables, images, code highlighting, and frontmatter property tables must be re-rendered natively before the web reader can be removed. Until then the web reader stays available.
- `PLANS.md` is reshaped around this decision.
