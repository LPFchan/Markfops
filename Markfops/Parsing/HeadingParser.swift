import Foundation

enum HeadingParser {

    /// Returns the text of the first H1 in the document, or nil.
    static func firstH1Title(in text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Returns the first letter of the first H1 title, uppercased.
    static func firstH1Letter(in text: String) -> String? {
        guard let title = firstH1Title(in: text),
              let first = title.first else { return nil }
        return String(first).uppercased()
    }

    /// Parses all ATX headings (# through ######) and returns HeadingNode array.
    /// Lines inside fenced code blocks (``` or ~~~) are ignored.
    static func parseHeadings(in text: String) -> [HeadingNode] {
        var nodes: [HeadingNode] = []
        let lines = text.components(separatedBy: "\n")
        var insideFence = false

        for (lineNumber, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Toggle fence state on opening/closing ``` or ~~~
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideFence.toggle()
                continue
            }
            guard !insideFence else { continue }
            guard trimmed.hasPrefix("#") else { continue }

            var level = 0
            for ch in trimmed {
                if ch == "#" { level += 1 } else { break }
            }
            guard level >= 1 && level <= 6 else { continue }

            let afterHashes = trimmed.dropFirst(level)
            guard afterHashes.hasPrefix(" ") || afterHashes.isEmpty else { continue }

            let title = afterHashes.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }

            nodes.append(HeadingNode(level: level, title: title, lineNumber: lineNumber))
        }

        return nodes
    }
}
