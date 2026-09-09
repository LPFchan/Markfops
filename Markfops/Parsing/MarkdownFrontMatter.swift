import Foundation

/// Describes the leading YAML frontmatter block, when a document has one.
///
/// `bodySource` keeps the original line structure and UTF-8 columns after the
/// frontmatter while replacing the frontmatter itself with spaces. That lets
/// cmark parse the Markdown body without treating YAML as a paragraph and
/// without shifting source positions.
struct MarkdownFrontMatter {
    struct Row {
        let key: String
        var valueLines: [String]
    }

    let bodySource: String
    let value: String
    let range: NSRange

    /// Treats unindented `key: value` lines as top-level properties and keeps
    /// indented or multiline YAML with the property that introduced it.
    static func rows(from value: String) -> [Row] {
        var rows: [Row] = []

        for line in value.components(separatedBy: "\n") {
            let startsAtTopLevel = line.first.map { !$0.isWhitespace } ?? false
            if startsAtTopLevel,
               !line.hasPrefix("#"),
               let separator = line.firstIndex(of: ":") {
                let key = line[..<separator].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    let valueStart = line.index(after: separator)
                    let rowValue = line[valueStart...].trimmingCharacters(in: .whitespaces)
                    rows.append(Row(key: key, valueLines: [rowValue]))
                    continue
                }
            }

            if rows.isEmpty {
                rows.append(Row(key: "", valueLines: [line]))
            } else {
                rows[rows.count - 1].valueLines.append(line)
            }
        }

        return rows
    }

    static func extract(from markdown: String) -> MarkdownFrontMatter? {
        let firstLineEnd = markdown.firstIndex(of: "\n") ?? markdown.endIndex
        guard delimiterText(markdown[..<firstLineEnd]) == "---" else {
            return nil
        }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard let closingIndex = lines.indices.dropFirst().first(where: {
                  let delimiter = delimiterText(lines[$0])
                  return delimiter == "---" || delimiter == "..."
              }) else {
            return nil
        }

        let value = lines[1..<closingIndex]
            .map { String($0.last == "\r" ? $0.dropLast() : $0) }
            .joined(separator: "\n")
        let bodySource = lines.enumerated().map { index, line in
            guard index <= closingIndex else { return String(line) }
            return String(line.map { character in
                character == "\r" ? "\r" : " "
            })
        }.joined(separator: "\n")

        // The closing line is part of the block. Its following line break stays
        // available to the source map as ordinary document text.
        let end = lines.prefix(closingIndex + 1).reduce(0) {
            $0 + $1.utf16.count
        } + closingIndex

        return MarkdownFrontMatter(
            bodySource: bodySource,
            value: value,
            range: NSRange(location: 0, length: end)
        )
    }

    private static func delimiterText(_ line: Substring) -> String {
        String(line.last == "\r" ? line.dropLast() : line)
    }
}
