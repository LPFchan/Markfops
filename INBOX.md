# Markfops Inbox

This file is an ephemeral scratch disk for capture waiting to be triaged.

Rules:

- Keep it easy to append to from external capture, operator notes, or agent capture.
- Use it as a pressure valve for untriaged capture, not as a backlog or brainstorm graveyard.
- Group related raw source events into one meaningful inbox entry when possible.
- Triage meaningful capture packets or clusters, not every raw source event and not an entire external history.
- During daily review, route, research, plan, discard, or leave capture; do not produce a giant project digest.
- It is okay to report counts or clusters of held, noisy, stale, or discarded items without summarizing every item.
- Do not update truth docs directly from inbox. Route through the orchestrator or an operator-approved decision.
- Remove entries once they are reflected into durable repo artifacts.
- Keep the stable `IBX-*` id even after the inbox entry itself is later deleted.
- Do not treat this file as durable truth.

## Active Capture

### IBX-20260409-001

- Opened: `2026-04-09 05-22-59 KST`
- Recorded by agent: `codex-markfops-repo-template-migration-20260409`
- Source: migrated from the retired research workspace file `open-questions.md`
- Source / capture ids: legacy `open-questions.md`
- Capture packet: implementation-framing questions about semantic parse and invalidation
- Received: unresolved engine-design questions from the research program
- Summary: decide what semantic parse and invalidation layer should replace today's split heading parsing and whole-document preview rendering
- Confidence: `high`
- Triage status: `in review`
- Triage decision: `research`
- Suggested destination: `PLANS.md` plus future `DEC-*`
- Related ids: `RSH-20260402-002`, `RSH-20260402-008`, `RSH-20260402-009`, `RSH-20260402-010`
- Notes:
  - Which richer structural pass should replace the split between `HeadingParser.parseHeadings(in:)` and `MarkdownRenderer.renderHTML(from:)`?
  - What minimum invalidation pipeline removes full preview body replacement from the hot path?
  - Does Markfops need a schema-level dual parse or serialize specification, or would that overfit the wrong architecture?

### IBX-20260409-002

- Opened: `2026-04-09 05-22-59 KST`
- Recorded by agent: `codex-markfops-repo-template-migration-20260409`
- Source: migrated from the retired research workspace file `open-questions.md`
- Source / capture ids: legacy `open-questions.md`
- Capture packet: implementation-framing questions about durable semantic identity and source mapping
- Received: unresolved identity and source-mapping questions from the research program
- Summary: decide the first durable semantic identity model and how it should layer over source spans without replacing Markdown-first truth
- Confidence: `high`
- Triage status: `in review`
- Triage decision: `research`
- Suggested destination: `PLANS.md` plus future `DEC-*`
- Related ids: `RSH-20260402-002`, `RSH-20260402-004`, `RSH-20260402-006`, `RSH-20260402-008`, `RSH-20260402-009`
- Notes:
  - What should be the first non-heading block identity primitive?
  - Should Markfops adopt a `SourceSpan`-style parser coordinate model and layer durable ids above it?
  - Where is the line between navigational anchors and durable semantic identity?
  - How should durable block identity survive Markdown-first editing without making blocks the canonical model?

### IBX-20260409-003

- Opened: `2026-04-09 05-22-59 KST`
- Recorded by agent: `codex-markfops-repo-template-migration-20260409`
- Source: migrated from the retired research workspace file `open-questions.md`
- Source / capture ids: legacy `open-questions.md`
- Capture packet: implementation-framing questions about dual-view viewport anchors and drift correction
- Received: unresolved synchronization questions from the research program
- Summary: decide the first hybrid viewport-anchor model and the drift-correction behavior for editor and preview
- Confidence: `high`
- Triage status: `in review`
- Triage decision: `research`
- Suggested destination: `PLANS.md` plus future `DEC-*`
- Related ids: `RSH-20260402-007`, `RSH-20260402-008`, `RSH-20260402-009`, `RSH-20260402-011`, `RSH-20260402-013`
- Notes:
  - What should be the primary viewport anchor: source line, block identity, layout fragment identity, semantic span identity, or a hybrid?
  - Should Markfops standardize on a dual-anchor model of shared ratio plus durable semantic block identity?
  - How should scroll drift be detected and corrected when editor and preview layouts diverge?
  - How early should preview-to-editor feedback channels become mandatory?

### IBX-20260409-004

- Opened: `2026-04-09 05-22-59 KST`
- Recorded by agent: `codex-markfops-repo-template-migration-20260409`
- Source: migrated from the retired research workspace file `open-questions.md`
- Source / capture ids: legacy `open-questions.md`
- Capture packet: implementation-framing questions about editor projection, block-aware editing, and semantic transitions
- Received: unresolved editor projection and transition questions from the research program
- Summary: decide how far the current `NSTextView` editor can stretch before Markfops needs a more explicit semantic scene or block-aware editing layer
- Confidence: `high`
- Triage status: `in review`
- Triage decision: `research`
- Suggested destination: `PLANS.md` plus future `DEC-*`
- Related ids: `RSH-20260402-005`, `RSH-20260402-006`, `RSH-20260402-008`, `RSH-20260402-009`, `RSH-20260402-012`
- Notes:
  - How far can semantic attributes in `NSTextView` go before a parallel semantic scene becomes necessary?
  - Which Markdown constructs can reuse source-line-targeted morphing safely, and which need a different transition strategy?
  - How much of Inkdown's block taxonomy should Markfops standardize early?
  - What is the minimum viewport-management layer needed if Markfops borrows row- or block-oriented ideas from SimpleBlockEditor?

## Daily Pressure Review Scratch

Use this section during a daily IBX review, then clear it after entries are routed, held, discarded, or escalated.

- Review date:
- Reviewer:
- Inbox pressure summary:
- Clusters reviewed:
- Promotion candidates:
- Research candidates:
- Plan candidates:
- Discard or purge candidates:
- Held without full summary:
- Operator route questions:

## Purge Rule

Once an item has been reflected into `SPEC.md`, `STATUS.md`, `PLANS.md`, `research/`, `records/decisions/`, `records/agent-worklogs/`, `upstream-intake/`, or a deliberate discard/hold note, remove the inbox entry.
