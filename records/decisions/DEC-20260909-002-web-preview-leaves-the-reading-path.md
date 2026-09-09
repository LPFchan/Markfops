# DEC-20260909-002: The Web Preview Leaves The Reading Path
Opened: 2026-09-09 19-50-00 KST
Recorded by agent: claude-torph-spike-20260909

## Metadata

- Status: accepted
- Deciders: operator
- Scope: engine architecture; supersedes the fallback consequence in `DEC-20260909-001`
- Related ids: `DEC-20260909-001`, `RSH-20260909-001`

## Decision

Formatted mode is the native reader. The `WKWebView` preview is removed from the app's reading path now, together with its bridge, its injected scripts, and the source-line and heading-id decoration of rendered HTML. The HTML pipeline remains only behind PDF export.

## Context

`DEC-20260909-001` kept the web preview reachable until the native reader covered tables, images, and code highlighting. Implementing that fallback produced a setting, a second code path through every mode-switch and find surface, and localization strings, all serving a view the product no longer wants.

## Options Considered

- Keep the web preview behind a setting until native parity
- Keep both surfaces and add a third mode
- Remove the web preview from the reading path now

## Rationale

The operator wants the two-step monospace-mode and formatted-mode dynamic, with one engine behind it. A fallback path doubles the surface that scroll sync, find, focus, and mode switching must handle, and it postpones the native gaps instead of exposing them. Removing it keeps one text engine and makes the gap list the plan.

## Consequences

- Tables, HTML blocks, and frontmatter render as raw monospaced text in formatted mode until native rendering lands. Images show alt text. Code blocks have no syntax highlighting. Find, replace, and heading commands are unavailable in formatted mode.
- `MarkdownRenderer` and `HTMLTemplate` serve PDF export only.
- `PLANS.md` drops the question of the web view's remaining role.
