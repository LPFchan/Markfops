import AppKit
import SwiftUI

/// Wraps an HTML fragment from cmark-gfm into a full page document.
/// CSS is inlined from the bundle files to avoid WKWebView sandboxing issues
/// with external file references when using loadHTMLString.
enum HTMLTemplate {

    static func page(body: String, isDark: Bool) -> String {
        let cssFileName = isDark ? "preview-dark" : "preview-light"
        let css = loadCSS(named: cssFileName)

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
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

    // MARK: - Private

    private static func loadCSS(named name: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "css"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        // Minimal fallback if bundle lookup fails
        return """
        body { font-family: -apple-system, sans-serif; padding: 32px; line-height: 1.65; }
        pre { background: #f6f8fa; padding: 16px; border-radius: 6px; overflow-x: auto; }
        code { font-family: monospace; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #d0d7de; padding: 8px 12px; }
        """
    }
}
