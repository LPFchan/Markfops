<p align="center">
  <img src=".github/assets/icon.png" width="128" alt="Markfops" />
</p>

<h1 align="center">Markfops</h1>

<p align="center">
  A fast, native macOS Markdown editor and reader.<br />
  No Electron — just Swift, SwiftUI, and AppKit.
</p>

https://github.com/user-attachments/assets/6106043c-bc84-4b4e-886f-851b95b03242

## Install

1. Download the latest `.dmg` from [Releases](https://github.com/LPFchan/Markfops/releases)
2. Open it and drag **Markfops** into **Applications**
3. First launch: macOS will warn that the app is unidentified. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**

Requires macOS 14 (Sonoma) or later. Markfops checks for its own updates from then on.

## What it does

- **Real Markdown** — full GitHub Flavored Markdown: tables, task lists, strikethrough, fenced code, autolinks
- **Edit or preview** any tab with `⌘⇧P`, with syntax highlighting while you write
- **Tabs and windows** that behave like macOS expects — drag tabs between windows, or tear one off into its own
- **Sidebar with table of contents** — expand any document to jump straight to a heading
- **Your files stay yours** — plain `.md` on disk, drag-and-drop to open, proxy icon in the title bar, PDF export
- **Light and dark** preview that follows your system appearance
- **Four languages** — English, 한국어, 日本語, 简体中文

## Keyboard shortcuts

| Action | | Action | |
|---|---|---|---|
| New document | ⌘N | Find | ⌘F |
| New tab | ⌘T | Find & Replace | ⌘⌥F |
| New window | ⌘⇧N | Bold | ⌘B |
| Open file | ⌘O | Italic | ⌘I |
| Save | ⌘S | Inline code | ⌘⌥K |
| Save As | ⌘⇧S | Undo / Redo | ⌘Z / ⌘⇧Z |
| Close tab | ⌘W | Next / previous tab | ⌘⇧] / ⌘⇧[ |
| Toggle edit / preview | ⌘⇧P | Preferences | ⌘, |

## Building from source

```bash
git clone https://github.com/LPFchan/Markfops.git
cd Markfops
xcodegen generate
open Markfops.xcodeproj   # then ⌘R
```

Needs Xcode 16+. The first build resolves Swift packages, so you'll want an internet connection.

<details>
<summary>Project layout and tech stack</summary>

```
Markfops/
├── App/           — Entry point, AppDelegate
├── Diagnostics/   — Instruments signposts for performance profiling
├── State/         — Document, DocumentStore, EditMode, HeadingNode
├── Views/         — SwiftUI views (sidebar, tab bar, editor container…)
├── Editor/        — NSTextView subclass + syntax highlighter
├── Renderer/      — cmark-gfm HTML renderer + HTML template
├── Parsing/       — Heading parser (TOC + favicon letter)
├── Commands/      — Keyboard shortcuts via CommandMenu
└── Resources/     — CSS stylesheets, asset catalog, localizations
```

| Layer | Technology |
|---|---|
| UI | SwiftUI + AppKit bridging |
| Markdown parsing | [libcmark_gfm](https://github.com/KristopherGBaker/libcmark_gfm) |
| Preview | WKWebView + custom CSS |
| Editor | NSTextView (TextKit 2) with a custom syntax highlighter |
| State | `@Observable` |
| Tab ordering | `OrderedDictionary` from [swift-collections](https://github.com/apple/swift-collections) |
| Updates | [Sparkle 2](https://sparkle-project.org) |

</details>

<details>
<summary>Profiling tab switches</summary>

The generated `Markfops` scheme profiles the Debug configuration so Instruments can load Sparkle under local ad-hoc signing. Archive builds use Release.

1. **Product → Profile**, select **Blank**, click **Choose**
2. Add the **Points of Interest** or **os_signpost** instrument with **+**
3. Record, switch between large documents a few times, stop
4. Filter the signpost track for the `com.markfops.Markfops` subsystem

The outer `Tab Switch` interval measures selection through the next main-loop turn after the native surface updates. Nested intervals separate document activation, editor creation or update, editor configuration, large-text comparison and synchronization, syntax highlighting, preview cache checks, Markdown rendering, preview loading, and preview DOM updates. `Surface Selected` also reports whether the tab was already warm.

</details>

## License

MIT — see [LICENSE](LICENSE).
