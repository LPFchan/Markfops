import AppKit

/// NSTextStorageDelegate that applies markdown syntax colors incrementally.
final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate {

    var configuration: EditorConfiguration = .default
    var isEnabled = true
    weak var textView: MarkdownNSTextView?
    private(set) var needsFullHighlight = true
    private var isHighlighting = false
    private var pendingCompositionRange: NSRange?

    var needsDeferredHighlight: Bool {
        needsFullHighlight || pendingCompositionRange != nil
    }

    private enum RuleColor {
        case heading
        case text
        case purple
        case orange
        case gray
        case teal
        case red
        case yellow
    }

    private struct Rule {
        let regex: NSRegularExpression
        let color: RuleColor
    }

    private static let rules: [Rule] = [
        Rule(regex: try! NSRegularExpression(pattern: #"^#{1,6}\s.+"#, options: [.anchorsMatchLines]), color: .heading),
        Rule(regex: try! NSRegularExpression(pattern: #"\*\*[^*\n]+\*\*|__[^_\n]+__"#), color: .text),
        Rule(regex: try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)([^*\n]+)(?<!\*)\*(?!\*)|(?<!_)_(?!_)([^_\n]+)(?<!_)_(?!_)"#), color: .purple),
        Rule(regex: try! NSRegularExpression(pattern: #"`[^`\n]+`"#), color: .orange),
        Rule(regex: try! NSRegularExpression(pattern: #"^```.*$"#, options: [.anchorsMatchLines]), color: .orange),
        Rule(regex: try! NSRegularExpression(pattern: #"^>.*"#, options: [.anchorsMatchLines]), color: .gray),
        Rule(regex: try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\([^)]+\)"#), color: .teal),
        Rule(regex: try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#), color: .teal),
        Rule(regex: try! NSRegularExpression(pattern: #"^[\-\*\+] "#, options: [.anchorsMatchLines]), color: .red),
        Rule(regex: try! NSRegularExpression(pattern: #"^\d+\. "#, options: [.anchorsMatchLines]), color: .red),
        Rule(regex: try! NSRegularExpression(pattern: #"^[\-\*] \[[ xX]\]"#, options: [.anchorsMatchLines]), color: .yellow),
        Rule(regex: try! NSRegularExpression(pattern: #"^(\*{3,}|-{3,}|_{3,})\s*$"#, options: [.anchorsMatchLines]), color: .gray),
    ]

    private static let headingRule = try! NSRegularExpression(
        pattern: #"^#{1,6}\s.+"#,
        options: [.anchorsMatchLines]
    )

    /// Updates the attributes that the highlighter owns. The caller can use the return value
    /// to avoid re-highlighting for incidental SwiftUI updates.
    @discardableResult
    func updateConfiguration(_ newConfiguration: EditorConfiguration) -> Bool {
        guard !configuration.isHighlightingEquivalent(to: newConfiguration) else { return false }
        configuration = newConfiguration
        if !isEnabled {
            needsFullHighlight = true
        }
        return true
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        guard isEnabled else {
            needsFullHighlight = true
            return
        }
        guard textView?.isComposingText != true else {
            rememberCompositionRange(in: textStorage, editedRange: editedRange)
            return
        }
        guard !isHighlighting else { return }
        let combinedRange = pendingCompositionRange.map { NSUnionRange($0, editedRange) } ?? editedRange
        pendingCompositionRange = nil
        let fullRange = lineRange(in: textStorage.string, for: combinedRange)
        highlight(textStorage: textStorage, in: fullRange)
    }

    /// Public entry point for full re-highlight (e.g. after programmatic text replacement).
    func highlightAll(in storage: NSTextStorage) {
        guard isEnabled else { return }
        guard textView?.isComposingText != true else {
            needsFullHighlight = true
            return
        }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            needsFullHighlight = false
            return
        }
        highlight(textStorage: storage, in: fullRange)
        needsFullHighlight = false
        pendingCompositionRange = nil
    }

    func flushDeferredHighlight(in storage: NSTextStorage) {
        guard isEnabled, textView?.isComposingText != true else { return }
        if needsFullHighlight {
            highlightAll(in: storage)
            return
        }
        guard let pendingCompositionRange else { return }
        self.pendingCompositionRange = nil
        let safeLocation = min(pendingCompositionRange.location, storage.length)
        let safeEnd = min(NSMaxRange(pendingCompositionRange), storage.length)
        let safeRange = NSRange(location: safeLocation, length: max(0, safeEnd - safeLocation))
        let fullRange = lineRange(in: storage.string, for: safeRange)
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

    private func rememberCompositionRange(in storage: NSTextStorage, editedRange: NSRange) {
        let fullRange = lineRange(in: storage.string, for: editedRange)
        pendingCompositionRange = pendingCompositionRange.map { NSUnionRange($0, fullRange) } ?? fullRange
    }

    private func highlight(textStorage: NSTextStorage, in range: NSRange) {
        guard isEnabled, range.length > 0, NSMaxRange(range) <= textStorage.length else { return }
        isHighlighting = true
        textStorage.beginEditing()
        defer {
            textStorage.endEditing()
            isHighlighting = false
        }

        textStorage.addAttribute(.foregroundColor, value: configuration.textColor, range: range)
        textStorage.addAttribute(.font, value: configuration.font, range: range)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = configuration.lineHeightMultiple
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        for rule in Self.rules {
            for match in rule.regex.matches(in: textStorage.string, range: range) {
                guard NSMaxRange(match.range) <= textStorage.length else { continue }
                textStorage.addAttribute(.foregroundColor, value: color(for: rule.color), range: match.range)
            }
        }

        // Bold font weight for headings
        for match in Self.headingRule.matches(in: textStorage.string, range: range) {
            guard NSMaxRange(match.range) <= textStorage.length else { continue }
            let boldFont = NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .bold)
            textStorage.addAttribute(.font, value: boldFont, range: match.range)
        }

        // The editor font does not contain every writing system. AppKit normally repairs
        // unsupported font runs while processing a character edit, but this highlighter runs
        // after that repair and replaces the font again. Repair the final attributes so Korean
        // and other fallback glyphs remain visible.
        textStorage.fixFontAttribute(in: range)
    }

    private func color(for ruleColor: RuleColor) -> NSColor {
        switch ruleColor {
        case .heading: return .systemBlue
        case .text: return configuration.textColor
        case .purple: return .systemPurple
        case .orange: return .systemOrange
        case .gray: return .systemGray
        case .teal: return .systemTeal
        case .red: return .systemRed
        case .yellow: return .systemYellow
        }
    }
}
