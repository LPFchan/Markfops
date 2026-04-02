import AppKit
import SwiftUI

/// Wraps an HTML fragment from cmark-gfm into a full page document.
/// CSS is inlined as Swift string constants to avoid any bundle lookup issues.
enum HTMLTemplate {

    static func page(body: String, isDark: Bool) -> String {
        let css = isDark ? darkCSS : lightCSS
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
        \(css)
          </style>
        </head>
        <body>
          <article class="markdown-body">
        \(body)
          </article>
        </body>
        </html>
        """
    }

    static func currentPage(body: String, colorScheme: ColorScheme? = nil) -> String {
        let isDark: Bool
        if let scheme = colorScheme {
            isDark = scheme == .dark
        } else {
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return page(body: body, isDark: isDark)
    }

    // MARK: - Inlined CSS

    private static let lightCSS = """
    :root {
      --text:        #1f2328;
      --bg:          #ffffff;
      --code-bg:     #f6f8fa;
      --code-border: #d0d7de;
      --border:      #d0d7de;
      --link:        #0969da;
      --blockquote:  #57606a;
      --th-bg:       #f6f8fa;
      --hr:          #d0d7de;
      --heading:     #1f2328;
      --body-wght:   430;
      --heading-wght: 650;
      --strong-wght: 620;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI Variable", "Segoe UI", Helvetica, Arial, sans-serif;
      font-size: 16px;
      line-height: 1.65;
      font-weight: 430;
      font-variation-settings: "wght" var(--body-wght);
      font-optical-sizing: auto;
      -webkit-font-smoothing: antialiased;
    }
    article.markdown-body {
      max-width: 780px;
      margin: 0 auto;
      padding: 40px 32px 80px;
    }
    article.markdown-body :is(p, li, blockquote, td, th) {
      font-variation-settings: "wght" var(--body-wght);
    }
    h1, h2, h3, h4, h5, h6 {
      color: var(--heading);
      font-weight: 650;
      font-variation-settings: "wght" var(--heading-wght);
      margin-top: 1.5em;
      margin-bottom: 0.5em;
      line-height: 1.3;
    }
    h1 { font-size: 2em;    border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
    h2 { font-size: 1.5em;  border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }
    h5 { font-size: 0.875em; }
    h6 { font-size: 0.85em;  color: var(--blockquote); }
    p { margin: 0.75em 0; }
    strong {
      font-weight: 620;
      font-variation-settings: "wght" var(--strong-wght);
    }
    em { font-style: italic; }
    del { text-decoration: line-through; color: var(--blockquote); }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
      font-family: "SF Mono", Menlo, Monaco, "Courier New", monospace;
      font-size: 0.875em;
      background: var(--code-bg);
      border: 1px solid var(--code-border);
      border-radius: 4px;
      padding: 0.15em 0.4em;
    }
    pre {
      background: var(--code-bg);
      border: 1px solid var(--code-border);
      border-radius: 8px;
      padding: 20px;
      overflow-x: auto;
      margin: 1.25em 0;
    }
    pre code {
      background: transparent;
      border: none;
      padding: 0;
      font-size: 0.875em;
      line-height: 1.6;
    }
    blockquote {
      border-left: 4px solid var(--border);
      color: var(--blockquote);
      margin: 1em 0;
      padding: 0.25em 1em;
    }
    blockquote p { margin: 0.25em 0; }
    ul, ol { padding-left: 2em; margin: 0.75em 0; }
    li { margin: 0.25em 0; }
    li > p { margin: 0.25em 0; }
    ul.contains-task-list { list-style: none; padding-left: 0.5em; }
    li.task-list-item { display: flex; align-items: flex-start; gap: 0.5em; }
    li.task-list-item input[type="checkbox"] { margin-top: 0.25em; accent-color: var(--link); }
    table { border-collapse: collapse; width: 100%; margin: 1.25em 0; font-size: 0.9em; }
    th, td { border: 1px solid var(--border); padding: 8px 14px; text-align: left; }
    thead tr { background: var(--th-bg); font-weight: 600; }
    tbody tr:nth-child(even) { background: var(--code-bg); }
    hr { border: none; border-top: 2px solid var(--hr); margin: 2em 0; }
    img { max-width: 100%; border-radius: 6px; display: block; margin: 1em auto; }
    .markfops-morphing-block {
      transition:
        font-size 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        font-weight 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        font-variation-settings 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        line-height 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        letter-spacing 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        margin-top 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        margin-bottom 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        padding-bottom 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        border-bottom-width 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        border-bottom-color 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        color 240ms cubic-bezier(0.2, 0.82, 0.2, 1);
      will-change: font-size, font-weight, font-variation-settings;
    }
    """

    private static let darkCSS = """
    :root {
      --text:        #e6edf3;
      --bg:          #0d1117;
      --code-bg:     #161b22;
      --code-border: #30363d;
      --border:      #30363d;
      --link:        #58a6ff;
      --blockquote:  #8b949e;
      --th-bg:       #161b22;
      --hr:          #30363d;
      --heading:     #e6edf3;
      --body-wght:   430;
      --heading-wght: 650;
      --strong-wght: 620;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI Variable", "Segoe UI", Helvetica, Arial, sans-serif;
      font-size: 16px;
      line-height: 1.65;
      font-weight: 430;
      font-variation-settings: "wght" var(--body-wght);
      font-optical-sizing: auto;
      -webkit-font-smoothing: antialiased;
    }
    article.markdown-body {
      max-width: 780px;
      margin: 0 auto;
      padding: 40px 32px 80px;
    }
    article.markdown-body :is(p, li, blockquote, td, th) {
      font-variation-settings: "wght" var(--body-wght);
    }
    h1, h2, h3, h4, h5, h6 {
      color: var(--heading);
      font-weight: 650;
      font-variation-settings: "wght" var(--heading-wght);
      margin-top: 1.5em;
      margin-bottom: 0.5em;
      line-height: 1.3;
    }
    h1 { font-size: 2em;    border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
    h2 { font-size: 1.5em;  border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }
    h5 { font-size: 0.875em; }
    h6 { font-size: 0.85em; color: var(--blockquote); }
    p { margin: 0.75em 0; }
    strong {
      font-weight: 620;
      font-variation-settings: "wght" var(--strong-wght);
    }
    em { font-style: italic; }
    del { text-decoration: line-through; color: var(--blockquote); }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
      font-family: "SF Mono", Menlo, Monaco, "Courier New", monospace;
      font-size: 0.875em;
      background: var(--code-bg);
      border: 1px solid var(--code-border);
      border-radius: 4px;
      padding: 0.15em 0.4em;
    }
    pre {
      background: var(--code-bg);
      border: 1px solid var(--code-border);
      border-radius: 8px;
      padding: 20px;
      overflow-x: auto;
      margin: 1.25em 0;
    }
    pre code {
      background: transparent;
      border: none;
      padding: 0;
      font-size: 0.875em;
      line-height: 1.6;
    }
    blockquote {
      border-left: 4px solid var(--border);
      color: var(--blockquote);
      margin: 1em 0;
      padding: 0.25em 1em;
    }
    blockquote p { margin: 0.25em 0; }
    ul, ol { padding-left: 2em; margin: 0.75em 0; }
    li { margin: 0.25em 0; }
    ul.contains-task-list { list-style: none; padding-left: 0.5em; }
    li.task-list-item { display: flex; align-items: flex-start; gap: 0.5em; }
    li.task-list-item input[type="checkbox"] { margin-top: 0.25em; accent-color: var(--link); }
    table { border-collapse: collapse; width: 100%; margin: 1.25em 0; font-size: 0.9em; }
    th, td { border: 1px solid var(--border); padding: 8px 14px; text-align: left; }
    thead tr { background: var(--th-bg); font-weight: 600; }
    tbody tr:nth-child(even) { background: rgba(255,255,255,0.03); }
    hr { border: none; border-top: 2px solid var(--hr); margin: 2em 0; }
    img { max-width: 100%; border-radius: 6px; display: block; margin: 1em auto; }
    .markfops-morphing-block {
      transition:
        font-size 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        font-weight 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        font-variation-settings 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        line-height 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        letter-spacing 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        margin-top 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        margin-bottom 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        padding-bottom 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        border-bottom-width 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        border-bottom-color 240ms cubic-bezier(0.2, 0.82, 0.2, 1),
        color 240ms cubic-bezier(0.2, 0.82, 0.2, 1);
      will-change: font-size, font-weight, font-variation-settings;
    }
    """
}
