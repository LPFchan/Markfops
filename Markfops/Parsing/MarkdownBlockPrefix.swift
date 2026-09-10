import Foundation

/// The leading block syntax of a source line: block-quote marks, heading
/// hashes, and list markers, with the whitespace that binds them. A keystroke
/// that changes it changes what block the line is, so formatted mode animates
/// that keystroke the way it animates a command, and leaves every other
/// keystroke instant.
enum MarkdownBlockPrefix {
    private static let run = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:[>#]+[ \t]*|[-*+][ \t]+|\d+[.)][ \t]+)*"#
    )

    /// The prefix run at the start of `line`, one line without its terminator.
    static func range(inLine line: NSString) -> NSRange {
        run.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length))?.range
            ?? NSRange(location: 0, length: 0)
    }

    /// Whether replacing `range` with `replacement` changes the prefix run of
    /// the line holding `range`. An edit that spans lines or inserts a line
    /// break changes more than one line's block and reports false; those
    /// edits stay instant.
    static func changes(in text: NSString, replacing range: NSRange, with replacement: String) -> Bool {
        guard range.location >= 0, NSMaxRange(range) <= text.length,
              !replacement.contains(where: \.isNewline) else { return false }
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: range.location, length: 0))
        guard NSMaxRange(range) <= contentsEnd else { return false }

        let oldLine = text.substring(with: NSRange(location: start, length: contentsEnd - start)) as NSString
        let newLine = oldLine.replacingCharacters(
            in: NSRange(location: range.location - start, length: range.length),
            with: replacement
        ) as NSString
        return oldLine.substring(with: self.range(inLine: oldLine)) != newLine.substring(with: self.range(inLine: newLine))
    }

    /// Whether `offset` sits inside a block whose lines are raw text (code,
    /// HTML, a table, front matter), where a `#` or `-` at the line start is
    /// content and not a marker.
    static func isInsideRawBlock(_ sourceMap: MarkdownSourceMap, offset: Int) -> Bool {
        isInsideRawBlock(sourceMap.span, offset: offset)
    }

    private static func isInsideRawBlock(_ span: MarkdownSourceMap.Span, offset: Int) -> Bool {
        guard span.range.location <= offset, offset <= NSMaxRange(span.range) else { return false }
        switch span.kind {
        case .codeBlock, .htmlBlock, .table, .frontMatter:
            return true
        default:
            return span.children.contains { isInsideRawBlock($0, offset: offset) }
        }
    }
}
