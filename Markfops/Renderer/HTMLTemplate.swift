import AppKit
import SwiftUI

/// Wraps an HTML fragment from cmark-gfm into a full page document.
enum HTMLTemplate {

    static func page(body: String, isDark: Bool) -> String {
        let theme = isDark ? "dark" : "light"
        let cssFile = "preview-\(theme).css"

        return """
        <!DOCTYPE html>
        <html data-theme="\(theme)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <link rel="stylesheet" href="\(cssFile)">
          <style>
            /* Inline syntax highlighting for code blocks (CSS-only fallback) */
            pre code { display: block; overflow-x: auto; }
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
}
