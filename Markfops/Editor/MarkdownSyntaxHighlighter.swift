import AppKit

/// NSTextStorageDelegate that applies markdown syntax colors incrementally.
final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate {

    var configuration: EditorConfiguration = .default
    private var isHighlighting = false

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters), !isHighlighting else { return }
        let fullRange = lineRange(in: textStorage.string, for: editedRange)
        highlight(textStorage: textStorage, in: fullRange)
    }

    /// Public entry point for full re-highlight (e.g. after programmatic text replacement).
    func highlightAll(in storage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        highlight(textStorage: storage, in: fullRange)
    }

    private func lineRange(in string: String, for range: NSRange) -> NSRange {
        let ns = string as NSString
        let safeRange = NSRange(
            location: min(range.location, ns.length),
            length: min(range.length, max(0, ns.length - range.location))
        )
        let lineStart = ns.lineRange(for: NSRange(location: safeRange.location, length: 0)).location
        let lineEnd = ns.lineRange(for: NSRange(location: NSMaxRange(safeRange), length: 0))
        return NSRange(location: lineStart, length: NSMaxRange(lineEnd) - lineStart)
    }

    private func highlight(textStorage: NSTextStorage, in range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length else { return }
        isHighlighting = true
        defer { isHighlighting = false }

        textStorage.addAttribute(.foregroundColor, value: configuration.textColor, range: range)
        textStorage.addAttribute(.font, value: configuration.font, range: range)

        struct Rule {
            let pattern: String
            let color: NSColor
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
        }

        let rules: [Rule] = [
            Rule(pattern: #"^#{1,6}\s.+"#, color: .systemBlue),
            Rule(pattern: #"\*\*[^*\n]+\*\*|__[^_\n]+__"#, color: .textColor, options: []),
            Rule(pattern: #"(?<!\*)\*(?!\*)([^*\n]+)(?<!\*)\*(?!\*)|(?<!_)_(?!_)([^_\n]+)(?<!_)_(?!_)"#, color: .systemPurple, options: []),
            Rule(pattern: #"`[^`\n]+`"#, color: .systemOrange, options: []),
            Rule(pattern: #"^```.*$"#, color: .systemOrange),
            Rule(pattern: #"^>.*"#, color: .systemGray),
            Rule(pattern: #"!\[([^\]]*)\]\([^)]+\)"#, color: .systemTeal, options: []),
            Rule(pattern: #"\[([^\]]+)\]\([^)]+\)"#, color: .systemTeal, options: []),
            Rule(pattern: #"^[\-\*\+] "#, color: .systemRed),
            Rule(pattern: #"^\d+\. "#, color: .systemRed),
            Rule(pattern: #"^[\-\*] \[[ xX]\]"#, color: .systemYellow),
            Rule(pattern: #"^(\*{3,}|-{3,}|_{3,})\s*$"#, color: .systemGray),
        ]

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            for match in regex.matches(in: textStorage.string, range: range) {
                guard NSMaxRange(match.range) <= textStorage.length else { continue }
                textStorage.addAttribute(.foregroundColor, value: rule.color, range: match.range)
            }
        }

        // Bold font weight for headings
        if let headingRegex = try? NSRegularExpression(pattern: #"^#{1,6}\s.+"#, options: [.anchorsMatchLines]) {
            for match in headingRegex.matches(in: textStorage.string, range: range) {
                guard NSMaxRange(match.range) <= textStorage.length else { continue }
                let boldFont = NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .bold)
                textStorage.addAttribute(.font, value: boldFont, range: match.range)
            }
        }
    }
}
