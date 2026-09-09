import Foundation
import libcmark_gfm

/// Converts raw Markdown text to an HTML fragment using cmark-gfm.
enum MarkdownRenderer {

    private struct RenderSource {
        let markdown: String
        let frontMatter: String?
    }

    static func renderHTML(from markdown: String) -> String {
        // Register GFM core extensions (tables, strikethrough, tasklists, autolinks)
        cmark_gfm_core_extensions_ensure_registered()

        let renderSource = renderSource(from: markdown)

        let options: Int32 = CMARK_OPT_UNSAFE | CMARK_OPT_SMART

        guard let parser = cmark_parser_new(options) else {
            return "<p><em>Failed to initialise markdown parser.</em></p>"
        }
        defer { cmark_parser_free(parser) }

        // Attach GFM extensions
        let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        // Feed the source text
        if let cStr = renderSource.markdown.cString(using: .utf8) {
            cmark_parser_feed(parser, cStr, cStr.count - 1)
        }

        guard let doc = cmark_parser_finish(parser) else {
            return "<p><em>Failed to parse document.</em></p>"
        }
        defer { cmark_node_free(doc) }

        // Pass the extensions list from the parser so GFM renderers (table, etc.) are invoked.
        let exts = cmark_parser_get_syntax_extensions(parser)
        guard let htmlPtr = cmark_render_html(doc, options, exts) else {
            return "<p><em>Render failed.</em></p>"
        }
        let html = String(cString: htmlPtr)
        free(htmlPtr)
        let htmlWithFrontMatter: String
        if let frontMatter = renderSource.frontMatter {
            htmlWithFrontMatter = renderFrontMatterHTML(frontMatter) + html
        } else {
            htmlWithFrontMatter = html
        }
        return htmlWithFrontMatter
    }

    /// Separates a complete leading YAML frontmatter block from the Markdown body.
    /// Its source lines stay blank in the parser input so the body is not parsed as YAML.
    private static func renderSource(from markdown: String) -> RenderSource {
        guard let frontMatter = MarkdownFrontMatter.extract(from: markdown) else {
            return RenderSource(markdown: markdown, frontMatter: nil)
        }
        return RenderSource(markdown: frontMatter.bodySource, frontMatter: frontMatter.value)
    }

    private static func renderFrontMatterHTML(_ frontMatter: String) -> String {
        let rows = MarkdownFrontMatter.rows(from: frontMatter)
        let body = rows.map { row in
            let value = escapeHTML(row.valueLines.joined(separator: "\n"))
            return "<tr><th scope=\"row\">\(escapeHTML(row.key))</th><td>\(value)</td></tr>"
        }.joined(separator: "\n")

        return """
        <table class="markfops-frontmatter" aria-label="YAML frontmatter">
        <thead><tr><th>Property</th><th>Value</th></tr></thead>
        <tbody>
        \(body)
        </tbody>
        </table>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

}
