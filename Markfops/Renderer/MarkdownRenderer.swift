import Foundation
import libcmark_gfm

/// Converts raw Markdown text to an HTML fragment using cmark-gfm.
enum MarkdownRenderer {

    static func renderHTML(from markdown: String) -> String {
        // Register GFM core extensions (tables, strikethrough, tasklists, autolinks)
        cmark_gfm_core_extensions_ensure_registered()

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
        if let cStr = markdown.cString(using: .utf8) {
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
        return injectHeadingIDs(into: html, using: markdown)
    }

    private static func injectHeadingIDs(into html: String, using markdown: String) -> String {
        let headings = HeadingParser.parseHeadings(in: markdown)
        guard !headings.isEmpty,
              let regex = try? NSRegularExpression(
                  pattern: #"<h([1-6])>(.*?)</h\1>"#,
                  options: [.dotMatchesLineSeparators]
              ) else {
            return html
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !matches.isEmpty else { return html }

        var replacements: [(NSRange, String)] = []
        var headingIndex = 0

        for match in matches {
            guard match.numberOfRanges == 3,
                  let levelRange = Range(match.range(at: 1), in: html),
                  let contentRange = Range(match.range(at: 2), in: html),
                  let level = Int(html[levelRange]) else {
                continue
            }

            while headingIndex < headings.count, headings[headingIndex].level != level {
                headingIndex += 1
            }
            guard headingIndex < headings.count else { break }

            let heading = headings[headingIndex]
            let innerHTML = html[contentRange]
            let replacement = "<h\(level) id=\"\(heading.domID)\">\(innerHTML)</h\(level)>"
            replacements.append((match.range, replacement))
            headingIndex += 1
        }

        var result = html
        for (range, replacement) in replacements.reversed() {
            guard let swiftRange = Range(range, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }
}
