# RSH-20260909-001: Torph-Style Glyph Morph Spike
Opened: 2026-09-09 16-36-14 KST
Recorded by agent: claude-torph-spike-20260909

Status: findings recorded; roadmap question open

## Question

The morphing research (`RSH-20260402-011`, `RSH-20260402-012`) stalled on the assumption that editor-to-reader text continuity needs a typeface that can interpolate between monospace and proportional forms. The web library torph (https://torph.lochie.me/) shows another route: swap each glyph to its destination font immediately, park it at its source x position, then slide every glyph to its destination x. Shape continuity is faked by position continuity.

Can Markfops do the same natively? Specifically: can TextKit hand back per-character positions cheaply enough, and does the result look right?

Evidence: `spikes/torph-glyph-morph/` (source, run instructions, snapshots in `evidence/`).

## Method

- Two-line sample: a `# ` heading and a paragraph with two inline code spans, 44 source characters.
- Two presentations built from the same tagged source characters. Source view: everything in SF Mono 15, syntax dimmed. Rendered view: syntax characters removed, prose in SF Pro 15, heading in SF Pro 28 bold, code in SF Mono 13.5 with a capsule.
- Both laid out with TextKit 1 (`NSLayoutManager`, `location(forGlyphAt:)`, `lineFragmentRect`, `boundingRect`), the same stack the Markfops editor uses. Every character's x, baseline, and advance read back and timed.
- Pairing is free here: the parser tags each source character, so each one either exists in both views (morph), only in the source view (syntax, fade out), or only in the rendered view (none in this sample, fade in).
- One `CALayer` per character per presentation, drawn once with Core Text. Baseline point interpolated; glyph bitmaps crossfade over the first 45% of the motion. Capsules interpolate from the backtick span to the code span.
- Two animation drivers compared: a display-link loop that reapplies all layer positions each frame on the main thread, and one Core Animation transaction that sets the end state and lets the render server interpolate.

## Findings

Machine: Apple Silicon Mac, macOS 15.7, 60 Hz display, release build.

| Measurement | Result |
| --- | --- |
| TextKit position readback, 43 characters | median 0.3 to 0.5 ms, p95 about 1 ms |
| Same, 37 characters (rendered view) | median 0.3 to 0.4 ms |
| First-ever layout in the process | 85 to 97 ms (font and TextKit warmup, paid once) |
| Layers for 44 characters | 82 (two per morphing character, one per removed syntax character, one per capsule) |
| Display-link driver, main-thread cost per frame | mean 0.95 ms, max 1.5 ms for 82 layers |
| Display-link driver, dropped frames | 3 long gaps on the very first run while glyph bitmaps rasterized; 0 on later runs |
| Core Animation driver, one-time setup | 2.0 to 2.3 ms for 82 layers, then no main-thread work per frame |

Visual result: the snapshots reproduce the torph effect. At the halfway frame, proportional glyphs sit at monospace spacing with visible gaps after narrow letters, and the heading is already bold and large while its letters are still spread on the monospace grid. The capsule visibly shrinks from the backticks onto the code.

## What This Settles

- Font interpolation is not needed. Measured positions plus a glyph swap look like a morph. The blocker named in the old research is gone.
- TextKit 1 can supply per-character geometry for a visible region in well under a frame. `RSH-20260402-013` feared layout timing would not be available early enough; for the editor side, it is.
- The editor and reader do not need a shared layout engine. Each side reports positions once before and once after. The coordinator only needs two snapshots, which matches the Transition Coordinator shape in `DEC-20260409-003`.
- The hard part is pairing, not motion. The spike got pairing for free because its parser tags every source character. In the real app that means the Markdown parser must expose which source characters are syntax and which survive into the rendered view, at inline granularity. That is the source-span and durable-identity work already accepted in `DEC-20260409-003`, made concrete one level down from blocks.

## What This Does Not Settle

- Scale. Costs grow linearly with characters. A full viewport of a few thousand characters would mean several thousand layers, tens of milliseconds per frame on the display-link driver, and a Core Animation setup around 100 ms if done naively. Per-glyph layers cannot be the default for everything.
- The reader side. Today's preview is `WKWebView`. The spike measured the rendered presentation with TextKit as a stand-in. Getting per-character rectangles out of the DOM is possible (`Range.getClientRects()` per character) but crosses a process boundary on every snapshot and was not tested.
- Ligatures. SF Pro forms ligatures such as "fi", which TextKit maps to one glyph for two characters. The sample avoided them. Pairing must be per glyph cluster, not per character, or ligatures must be disabled during the morph.
- Line wrapping. Both presentations fit on one line each. When a paragraph wraps differently in the two fonts, characters near the wrap point jump between lines; the same math handles it but it has not been looked at.
- 120 Hz. The test display ran at 60 Hz.
- Caret, selection, and input-method composition during the transition. Not touched.
- Korean, emoji, and right-to-left text. Not tested.

## Design Implications Worth Keeping

- Hand the motion to Core Animation. The display-link driver is only useful for scrubbing and measurement. The production path should set end states in one transaction and let the render server interpolate.
- Split per glyph only where it pays. Prose words could move as single layers with a crossfade, and per-glyph splitting could be reserved for the block under the caret or the viewport center, where the eye is. This is the dial that decides whether the technique scales, and it needs its own measurement.
- Read glyph geometry off the live `NSLayoutManager` of the editor rather than a throwaway one. The editor has already paid for layout.
- Keep the crossfade short. At a quarter of the way through, both glyph sets are visible on top of each other. A shorter swap window or an instant swap past a threshold would read cleaner.

## Open Questions

- Should the first real spike inside the app target the mode switch (whole viewport) or a single inline transition such as typing a closing backtick (one span)? The single-span case is the cheap win and matches the torph demo exactly.
- How should pairing work when the rendered view is still WebKit? Options: measure the DOM per character over the message bridge, or move the animated region to a native overlay that renders both presentations itself while the web view is hidden underneath.
- What per-word versus per-glyph split keeps a 4,000-character viewport under one frame of setup?

## Roadmap Question For The Operator

`RSH-20260402-010` sequences transition work as Phase D, after semantic block identity and scroll synchronization. This spike shows the motion itself is cheap and the dependency is narrower than assumed: inline-level source spans, not the full block scene. Whether to pull a single-span in-app transition spike ahead of the block identity work is a product call and is not decided here.
