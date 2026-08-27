import Foundation
import libcmark_gfm

/// Converts raw Markdown text to an HTML fragment using cmark-gfm.
enum MarkdownRenderer {

    private struct PreviewSource {
        let markdown: String
        let frontMatter: String?
    }

    private struct FrontMatterRow {
        let key: String
        var valueLines: [String]
    }

    private static let sourceLineAttributeRegex = try? NSRegularExpression(
        pattern: #"data-markfops-source-line=\"(\d+)\""#
    )

    static func renderHTML(from markdown: String) -> String {
        // Register GFM core extensions (tables, strikethrough, tasklists, autolinks)
        cmark_gfm_core_extensions_ensure_registered()

        let previewSource = previewSource(from: markdown)

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
        if let cStr = previewSource.markdown.cString(using: .utf8) {
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
        let htmlWithFrontMatter: String
        if let frontMatter = previewSource.frontMatter {
            htmlWithFrontMatter = renderFrontMatterHTML(frontMatter) + htmlWithSourceLines
        } else {
            htmlWithFrontMatter = htmlWithSourceLines
        }
        return injectHeadingIDs(into: htmlWithFrontMatter, using: markdown)
    }

    /// Separates a complete leading YAML frontmatter block from the Markdown body.
    /// Its source lines stay blank in the parser input so body anchors still match the editor.
    private static func previewSource(from markdown: String) -> PreviewSource {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first.map(delimiterText) == "---",
              let closingIndex = lines.indices.dropFirst().first(where: {
                  let delimiter = delimiterText(lines[$0])
                  return delimiter == "---" || delimiter == "..."
              }) else {
            return PreviewSource(markdown: markdown, frontMatter: nil)
        }

        let frontMatter = lines[1..<closingIndex]
            .map { String($0.last == "\r" ? $0.dropLast() : $0) }
            .joined(separator: "\n")
        let bodySource = lines.enumerated().map { index, line in
            guard index <= closingIndex else { return String(line) }
            return String(line.map { $0 == "\r" ? "\r" : " " })
        }.joined(separator: "\n")
        return PreviewSource(markdown: bodySource, frontMatter: frontMatter)
    }

    private static func delimiterText(_ line: Substring) -> String {
        String(line.last == "\r" ? line.dropLast() : line)
    }

    private static func renderFrontMatterHTML(_ frontMatter: String) -> String {
        let rows = frontMatterRows(from: frontMatter)
        let body = rows.map { row in
            let value = escapeHTML(row.valueLines.joined(separator: "\n"))
            return "<tr><th scope=\"row\">\(escapeHTML(row.key))</th><td>\(value)</td></tr>"
        }.joined(separator: "\n")

        return """
        <table class="markfops-frontmatter" data-markfops-source-line="0" aria-label="YAML frontmatter">
        <thead><tr><th>Property</th><th>Value</th></tr></thead>
        <tbody>
        \(body)
        </tbody>
        </table>
        """
    }

    /// Treats unindented `key: value` lines as top-level properties and keeps
    /// indented or multiline YAML with the property that introduced it.
    private static func frontMatterRows(from frontMatter: String) -> [FrontMatterRow] {
        var rows: [FrontMatterRow] = []

        for line in frontMatter.components(separatedBy: "\n") {
            let startsAtTopLevel = line.first.map { !$0.isWhitespace } ?? false
            if startsAtTopLevel,
               !line.hasPrefix("#"),
               let separator = line.firstIndex(of: ":") {
                let key = line[..<separator].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    let valueStart = line.index(after: separator)
                    let value = line[valueStart...].trimmingCharacters(in: .whitespaces)
                    rows.append(FrontMatterRow(key: key, valueLines: [value]))
                    continue
                }
            }

            if rows.isEmpty {
                rows.append(FrontMatterRow(key: "", valueLines: [line]))
            } else {
                rows[rows.count - 1].valueLines.append(line)
            }
        }

        return rows
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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

        // Build the result once from the original UTF-16 ranges. Replacing each match in
        // reverse repeatedly walks and copies the growing Swift String for long documents.
        let source = html as NSString
        var pieces: [String] = []
        pieces.reserveCapacity(matches.count * 2 + 1)
        var cursor = 0

        for match in matches {
            let fullRange = match.range(at: 0)
            guard fullRange.location >= cursor,
                  NSMaxRange(fullRange) <= source.length else {
                continue
            }

            pieces.append(source.substring(with: NSRange(
                location: cursor,
                length: fullRange.location - cursor
            )))

            let tag = source.substring(with: fullRange)
            if tag.contains("data-markfops-source-line=") {
                pieces.append(tag)
            } else {
                guard let sourceLine = Int(source.substring(with: match.range(at: 3))) else {
                    pieces.append(tag)
                    cursor = NSMaxRange(fullRange)
                    continue
                }
                pieces.append(String(tag.dropLast()))
                pieces.append(" data-markfops-source-line=\"\(max(0, sourceLine - 1))\">")
            }
            cursor = NSMaxRange(fullRange)
        }

        pieces.append(source.substring(from: cursor))
        return pieces.joined()
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
        guard let regex = sourceLineAttributeRegex,
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
