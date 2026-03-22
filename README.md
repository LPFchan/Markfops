# Markfops

A lightweight, native macOS Markdown reader and editor. No Electron — built with Swift + SwiftUI.

## Features

- **Full GFM support** — tables, task lists, strikethrough, fenced code blocks, autolinks
- **Edit / Preview mode** per tab (⌘⇧P to toggle)
- **Vertical sidebar** with document list — like Notes or ChatGPT
- **Horizontal tab bar** with favicon-style letter badges
- **Table of contents** — click the ▶ triangle in the sidebar to expand a document's headings; click any heading to jump to it in the editor or preview
- **Favicon letter** — the first letter of the H1 heading shown in both sidebar and tab bar
- **Drag and drop** — drag any `.md` file onto the app window to open it; title-bar proxy icon for macOS-native drag behaviour (Cmd+click to see path)
- **Full keyboard shortcuts** on-par with macOS TextEdit (see below)
- **Syntax highlighting** in the editor (headings, bold, italic, code, links, blockquotes, tables…)
- **Light and dark mode** preview — automatically follows System Appearance

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16 or later

## Building

```bash
git clone https://github.com/YOUR_USERNAME/Markfops.git
cd Markfops
xcodegen generate        # generates Markfops.xcodeproj
open Markfops.xcodeproj  # then press ⌘R
```

> **First run:** Xcode will resolve Swift Package dependencies (libcmark_gfm, swift-collections) automatically. This requires an internet connection on the first build.

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| New document | ⌘N |
| New tab | ⌘T |
| Open file | ⌘O |
| Save | ⌘S |
| Save As | ⌘⇧S |
| Close tab | ⌘W |
| Toggle Edit / Preview | ⌘⇧P |
| Next tab | ⌘⇧] |
| Previous tab | ⌘⇧[ |
| Find | ⌘F |
| Find & Replace | ⌘⌥F |
| Bold | ⌘B |
| Italic | ⌘I |
| Inline Code | ⌘⌥K |
| Undo / Redo | ⌘Z / ⌘⇧Z |
| Preferences | ⌘, |
| Quit | ⌘Q |

## Project Structure

```
Markfops/
├── App/           — Entry point, AppDelegate
├── State/         — Document, DocumentStore, EditMode, HeadingNode
├── Views/         — All SwiftUI views (sidebar, tab bar, editor container…)
├── Editor/        — NSTextView subclass + syntax highlighter
├── Renderer/      — cmark-gfm HTML renderer + HTML template
├── Parsing/       — Heading parser (for TOC + favicon letter)
├── Commands/      — Keyboard shortcuts via CommandMenu
└── Resources/     — CSS stylesheets, asset catalog
```

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI + AppKit bridging |
| Markdown parsing | [libcmark_gfm](https://github.com/KristopherGBaker/libcmark_gfm) (GFM reference implementation) |
| Preview | WKWebView + custom CSS |
| Editor | NSTextView (TextKit 2) with custom syntax highlighter |
| State | `@Observable` (Swift 5.9+) |
| Tab ordering | `OrderedDictionary` from [swift-collections](https://github.com/apple/swift-collections) |

## License

MIT — see [LICENSE](LICENSE) for details.
