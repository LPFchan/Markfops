# Torph glyph morph spike

Question: can Markfops animate text between the editor presentation (monospace, syntax visible) and the reader presentation (proportional, syntax hidden) by measuring every character's position in both layouts and sliding each glyph from one to the other, the way [torph](https://torph.lochie.me/) does on the web?

Findings live in `records/research/RSH-20260909-001-torph-glyph-morph-spike.md`.

## What it does

- Parses a two-line Markdown sample (`# ` heading, two inline code spans) into source characters tagged prose, heading, code, or syntax.
- Builds two attributed strings from those characters: the source view keeps everything in SF Mono, the rendered view drops syntax characters and styles the rest.
- Lays both out with TextKit 1 (`NSLayoutManager`, the same stack as the Markfops editor) and reads back every character's x, baseline, and advance. This is timed.
- Creates one `CALayer` per character per presentation, each drawn once with Core Text, plus one layer per inline-code capsule.
- Morphs by interpolating each character's baseline point between the two layouts while crossfading the two glyph bitmaps. Deleted syntax fades out in place. The capsule shrinks from the backtick span onto the code.
- Offers two animation drivers: a display-link loop that reapplies positions every frame on the main thread, and a one-shot Core Animation transaction.

## Run

```sh
cd spikes/torph-glyph-morph
swift build -c release
.build/release/TorphGlyphMorph              # window: space morphs via display link, c morphs via Core Animation, slider scrubs
.build/release/TorphGlyphMorph --auto       # plays both drivers once each, prints frame stats, quits
.build/release/TorphGlyphMorph --bench      # headless: 300 TextKit measurement passes per presentation
.build/release/TorphGlyphMorph --snapshot /tmp/out   # writes morph-000..100.png at five progress values
```

`evidence/` holds three snapshots from the run recorded in the memo.
