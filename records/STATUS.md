# Markfops Status

This document tracks current operational truth.
Update it when the project's real state changes.
Do not use it as a transcript or a scratchpad.

## Snapshot

- Last updated: 2026-09-02
- Overall posture: `active`
- Current focus: keep the published `1.1.2` baseline stable while the next release accumulates
- Highest-priority blocker: none; the public `1.1.2` DMG and Sparkle update are verified
- Next operator decision needed: choose the scope and timing of the next release when enough work accumulates
- Related decisions: `DEC-20260409-001`, `DEC-20260409-002`, `DEC-20260409-003`, `DEC-20260410-001`

## Current State Summary

Markfops is a working native macOS Markdown app with XcodeGen project generation, GitHub Actions build and release workflows, Sparkle publishing assets, and a meaningful research corpus for a future native WYSIWYG engine. Each document window now owns its own tabs, while an app-level coordinator routes external files, tab transfers, close handling, and recovery across windows. External Markdown files join the most recently active window, and reopening a file focuses its existing tab instead of creating another copy. Existing scenes accept Finder and Dock file events, simultaneous scene creation cannot bind multiple windows to the same tab catalog, and file-open focus requests survive SwiftUI window creation. A cold Finder launch explicitly presents the requested document window, preserves restored tabs when SwiftUI discards its transient startup scene, and deduplicates every in-flight scene request until the window registers. Build and release workflows exercise this exact cold-launch path with isolated recovery data. Each window keeps a file watcher only for its active document; inactive documents are checked and reloaded when selected. Multi-file opens load every requested document before selecting the final tab, preventing watcher and rendering churn from exhausting the process file-descriptor limit. The active document's table of contents opens by default in the sidebar. Each document keeps its content scroll position across tab switches. Manually scrolling the sidebar pauses table-of-contents following until the user scrolls the content again, including within the same heading, while restoration and heading-jump animations do not resume following. The automatic table-of-contents animation ignores requests that are already at their live target and eases into its destination with a critically damped final approach and settles only when close to the target and nearly at rest, so follow animations finish without a visible jolt and keep the main thread idle after navigation and mode switches. In edit mode, table-of-contents following uses the source position at the viewport center, so wrapped lines do not make the highlighted heading drift away from the visible content. Mode switches transfer that same center source line between editor and preview, using the saved scroll percentage only when a source anchor is unavailable. Preview renders complete leading YAML frontmatter as a property table while preserving original source-line positions for editor and preview synchronization. Clicking a table-of-contents heading highlights its exact source line, including in documents containing emoji, Korean, or other text whose AppKit offsets differ from Swift character counts. Sidebar rows use cached document metadata, table-of-contents rows are derived in one pass, and each file type shares one immediately available system icon. Unvisited collapsed documents stay as plain lazy rows, while visited documents retain stable table-of-contents sections so tab switches animate their contents and restore the exact previously active heading. Multiple expanded tables of contents retain independent pinned sections while navigation stays responsive with hundreds of open documents. Compact mode lazily renders only the visible horizontal tab pills and opens centered on the active tab, so switching layouts and scrolling the strip remain responsive with the same document load. Sidebar transitions hide toolbar content before the visibility change, wait for both AppKit's layout and presented frame to reach the endpoint, then swap native-title and compact-tab ownership while hidden before fading the toolbar back in; the ownership resize cannot restart a hidden transition. Each visited tab keeps its native editor and preview mounted, while unvisited tabs remain cheap and only the selected tab stays interactive, so returning to a tab preserves its live view instead of rebuilding it. Hidden native surfaces cannot take keyboard focus, while the selected editor or preview receives first-responder ownership without interrupting active text fields. The active editor and preview stay warm across mode changes, unchanged previews reuse rendered content, and hidden editors defer full-document syntax work until their text or appearance actually changes. Edit-mode syntax highlighting leaves active input-method composition untouched and repairs unsupported font runs afterward, so Korean and other writing systems remain visible and compose normally. The app-menu and Settings update controls receive the app-owned Sparkle controller directly, so both initiate a visible update check. Undo and redo history belongs to each document and survives tab or window moves, and the release workflow gates packaging on the full test suite. The release pipeline derives the bundle version from the release tag, applies the release-only entitlement needed for ad-hoc Sparkle loading, and verifies the signature, entitlement, version, and both ordinary and Finder-driven cold launches before publishing. Version `1.1.2` is published, its public DMG passes checksum, disk-image, version, signature, and cold Finder launch checks, and its signed update is present in the live Sparkle feed. The installer uses a plain cocoa background with stable, unversioned installation wording. The app ships a real icon, an MIT license, and a README written for people downloading the app rather than building it.

## Active Phases Or Tracks

### Core App Baseline

- Goal: preserve and ship the current native Markdown editor, preview, navigation, and packaging pipeline
- Status: `in progress`
- Why this matters now: the current product remains the foundation that future engine work must not destabilize
- Current work: maintain the existing app structure, tests, release workflows, and Sparkle assets while research and planning continue
- Exit criteria: baseline app workflows remain healthy during repo and architecture work
- Dependencies: `Markfops/`, `MarkfopsTests/`, `project.yml`, GitHub Actions
- Risks: future engine experiments could compromise Markdown fidelity or native feel if they skip the accepted constraints
- Related ids: `RSH-20260402-002`, `DEC-20260409-002`

### Native WYSIWYG Engine Research And Framing

- Goal: convert completed archaeology into an implementation-ready architecture and first spike
- Status: `in progress`
- Why this matters now: the repo has enough accepted research to move from exploration toward execution
- Current work: complete the roadmap, transition coverage, morphing strategy, risk framing, and first-spike selection
- Exit criteria: implementation framing docs are filled in and the first concrete spike is chosen
- Dependencies: `RSH-20260402-007` through `RSH-20260402-013`
- Risks: unresolved questions around semantic identity, invalidation, and synchronization can still create drift in early implementation choices
- Related ids: `DEC-20260409-002`, `DEC-20260409-003`, `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`, `IBX-20260409-004`

## Recent Changes To Project Reality

- Date: 2026-09-02
  - Change: `1.1.2` shipped immediate cold Finder file opens with preserved restored sessions, with the signed DMG and Sparkle update published publicly
  - Why it matters: double-clicking a Markdown file no longer leaves Markfops windowless until its Dock icon is clicked, and launch recovery no longer loses or duplicates saved windows while repairing that path
  - Related ids: `LOG-20260902-143904-260902`, `LOG-20260902-144616-260902`

- Date: 2026-09-02
  - Change: `1.1.1` shipped working app-menu and Settings update controls, with the signed DMG and Sparkle update published publicly
  - Why it matters: user-initiated update checks open Sparkle instead of silently returning through SwiftUI's internal application delegate, and existing installations can receive the repair through the normal updater
  - Related ids: `LOG-20260902-043709-260902`, `LOG-20260902-045318-elease`

- Date: 2026-09-02
  - Change: `1.1.0` shipped reliable input-method composition and visible font fallback, with the signed DMG and Sparkle update published publicly
  - Why it matters: Korean and other writing systems no longer become invisible or get split apart while typing, and existing installations can receive the fix through the normal updater
  - Related ids: `LOG-20260902-040740-260902`, `LOG-20260902-041616-elease`

- Date: 2026-08-27
  - Change: `1.0.3` shipped YAML frontmatter property tables in Preview, with the signed DMG and Sparkle update published publicly
  - Why it matters: frontmatter remains visible and readable without being misinterpreted as a giant Markdown heading, and existing installations can receive the change through the normal updater
  - Related ids: `LOG-20260827-144637-260827`, `LOG-20260827-152352-elease`

- Date: 2026-08-27
  - Change: `1.0.1` shipped with launch-safe ad-hoc Sparkle signing, and the next-release DMG design now uses a solid icon-matched background with unversioned installation wording
  - Why it matters: the published app launches without an Apple Developer certificate, and future installer artwork stays consistent across version tags
  - Related ids: `LOG-20260826-235841-260826`, `LOG-20260827-001608-260827`

- Date: 2026-08-26
  - Change: the release pipeline became capable of producing an installable, updatable app, and the app gained its icon
  - Why it matters: the archived bundle previously had no usable signature and a hardcoded version, so Sparkle could never have offered an update and some macOS versions would refuse to launch it; the asset catalog was also never compiled, so the app had no icon at all
  - Related ids: `LOG-20260826-232032-eopus5`, `LOG-20260826-232746-eopus5`

- Date: 2026-08-26
  - Change: visited sidebar documents retain stable table-of-contents sections, and tab restoration keeps a valid source-derived active heading
  - Why it matters: switching tabs animates each table of contents open and closed while returning to the exact heading that was active before the switch; unvisited documents remain lightweight rows
  - Related ids: none yet

- Date: 2026-08-26
  - Change: selected editor and preview surfaces now own native keyboard focus, hidden warm surfaces reject first-responder status, and file-open activation requests wait for their SwiftUI window to register
  - Why it matters: launches and tab switches no longer leave keyboard input attached to an invisible surface, while cold Finder opens still activate the intended document window
  - Related ids: none yet

- Date: 2026-08-26
  - Change: each visited tab now retains its native editor and preview surfaces in a stable per-window detail host, including across compact-toolbar ownership changes; editor and preview caches use revision counters, and lifecycle/state signposts identify any future teardown trigger
  - Why it matters: switching tabs no longer recreates the text view or reloads the preview from scratch, and unrelated view updates no longer compare complete large-document strings
  - Related ids: none yet

- Date: 2026-04-02
  - Change: the research program added rigorous two-view scroll synchronization as a first-class objective
  - Why it matters: future architecture work now has a higher bar than simple preview parity
  - Related ids: `DEC-20260409-002`
- Date: 2026-04-03
  - Change: reference deep dives and synthesis artifacts were completed and accepted
  - Why it matters: implementation framing can begin without reopening the full archaeology pass
  - Related ids: `RSH-20260402-003` through `RSH-20260402-009`
- Date: 2026-04-09
  - Change: canonical repo truth moved to root operating surfaces and records
  - Why it matters: future work now has stable routing, provenance expectations, and durable artifact locations
  - Related ids: `DEC-20260409-001`, `LOG-20260410-230133-logmig`
- Date: 2026-04-10
  - Change: commit-backed `LOG-*` execution history replaced the legacy markdown execution-history surface
  - Why it matters: execution records now live in git history, the retired markdown surface no longer exists, and provenance stays recoverable without a parallel file layer
  - Related ids: `DEC-20260410-001`, `LOG-20260410-230133-logmig`
- Date: 2026-08-24
  - Change: document handling gained explicit per-window ownership, coordinated external opens and recovery, transferable tabs, document-scoped undo history, active-document-only file watching, and batched multi-file opening; edit-mode syntax highlighting became stable; editor and preview surfaces now remain warm across mode changes; compact tabs now remain warm across sidebar transitions while the native document title and sidebar controls retain their platform behavior; table-of-contents animation now settles deterministically; CI began enforcing renderer, highlighting, undo, and watcher tests
  - Why it matters: new windows and detached tabs remain independent, external files join the active window without duplicate state, large file sets no longer exhaust the process file-descriptor limit, long documents switch modes without rebuilding both native surfaces, sidebar transitions no longer rebuild the compact tab graph, wide compact windows devote the available toolbar space to tabs, the native title continues exposing the draggable file proxy, repeating unchanged rendering and highlighting no longer consumes transition time, sidebar animation work settles cleanly, undo and redo survive editor recreation and document moves, editor colors no longer disappear during view updates, and regressions now fail the build
  - Related ids: none yet
- Date: 2026-08-25
  - Change: sidebar transitions preserve the native visibility transaction while staging toolbar ownership at the visible endpoint; ordinary compact-mode window resizing is excluded from transition masking and refreshes only the live compact toolbar width
  - Why it matters: sidebar expansion and collapse remain animated, compact tabs and the native title stay hidden only while AppKit rearranges them, and resizing the window no longer makes the toolbar disappear or invalidates the hidden 200-tab strip
  - Related ids: none yet

## Active Blockers And Risks

- Blocker or risk: first implementation spike is not selected yet
  - Effect: the project can continue refining architecture without turning accepted direction into code
  - Owner: operator plus orchestrator
  - Mitigation: finish the framing docs and route the remaining open questions into a small first spike
  - Related ids: `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`, `IBX-20260409-004`

## Immediate Next Steps

- Next: accumulate and verify changes for the next release
  - Owner: orchestrator plus the release workflow
  - Trigger: accepted product work changes the published `1.1.2` baseline
  - Related ids: `STATUS.md`
- Next: finish `RSH-20260402-010` through `RSH-20260402-013`
  - Owner: orchestrator with operator review
  - Trigger: the `1.0.0` release is published
  - Related ids: `RSH-20260402-010`, `RSH-20260402-011`, `RSH-20260402-012`, `RSH-20260402-013`
- Next: choose and execute the first implementation spike
  - Owner: operator plus implementation agent
  - Trigger: framing docs and open intake are synthesized into a bounded task
  - Related ids: `PLANS.md`, `IBX-20260409-001`, `IBX-20260409-002`, `IBX-20260409-003`
