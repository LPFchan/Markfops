import Foundation
import libcmark_gfm

/// Converts raw Markdown text to an HTML fragment using cmark-gfm.
enum MarkdownRenderer {

    static func renderHTML(from markdown: String) -> String {
        // Register GFM core extensions (tables, strikethrough, tasklists, autolinks)
        cmark_gfm_core_extensions_ensure_registered()

        let options: Int32 = CMARK_OPT_UNSAFE | CMARK_OPT_SMART | CMARK_OPT_SOURCEPOS

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
        let htmlWithSourceLines = injectSourceLineAttributes(into: html)
        return injectHeadingIDs(into: htmlWithSourceLines, using: markdown)
    }

    private static func injectSourceLineAttributes(into html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-z][a-z0-9]*)([^>]*\sdata-sourcepos=\"(\d+):\d+-\d+:\d+\"[^>]*)>"#,
            options: [.caseInsensitive]
        ) else {
            return html
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !matches.isEmpty else { return html }

        var updatedHTML = html
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: updatedHTML),
                  let sourceLineRange = Range(match.range(at: 3), in: updatedHTML),
                  let sourceLine = Int(updatedHTML[sourceLineRange]) else {
                continue
            }

            let tag = String(updatedHTML[fullRange])
            guard !tag.contains("data-markfops-source-line=") else { continue }
            let replacement = String(tag.dropLast()) + " data-markfops-source-line=\"\(max(0, sourceLine - 1))\">"
            updatedHTML.replaceSubrange(fullRange, with: replacement)
        }

        return updatedHTML
    }

    private static func injectHeadingIDs(into html: String, using markdown: String) -> String {
        let headings = HeadingParser.parseHeadings(in: markdown)
        guard !headings.isEmpty,
              let regex = try? NSRegularExpression(
                  pattern: #"<h([1-6])([^>]*)>(.*?)</h\1>"#,
                  options: [.dotMatchesLineSeparators]
              ) else {
            return html
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !matches.isEmpty else { return html }

        var replacements: [(NSRange, String)] = []

        for match in matches {
            guard match.numberOfRanges == 4,
                  let levelRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html),
                  let contentRange = Range(match.range(at: 3), in: html),
                  let level = Int(html[levelRange]) else {
                continue
            }

            let attributes = String(html[attributesRange])
            guard let sourceLine = sourceLine(from: attributes),
                  let heading = headings.first(where: { $0.lineNumber == sourceLine && $0.level == level }) else {
                continue
            }

            let innerHTML = html[contentRange]
            let replacement = "<h\(level)\(sanitizedHeadingAttributes(from: attributes)) id=\"\(heading.domID)\">\(innerHTML)</h\(level)>"
            replacements.append((match.range, replacement))
        }

        var result = html
        for (range, replacement) in replacements.reversed() {
            guard let swiftRange = Range(range, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }

    private static func sourceLine(from attributes: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"data-markfops-source-line=\"(\d+)\""#
        ),
        let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
        let range = Range(match.range(at: 1), in: attributes) else {
            return nil
        }
        return Int(attributes[range])
    }

    private static func sanitizedHeadingAttributes(from attributes: String) -> String {
        var sanitized = attributes.replacingOccurrences(
            of: #"\sid=\"[^\"]*\""#,
            with: "",
            options: .regularExpression
        )
        if sanitized.isEmpty || sanitized.hasPrefix(" ") {
            return sanitized
        }
        sanitized.insert(" ", at: sanitized.startIndex)
        return sanitized
    }
}
