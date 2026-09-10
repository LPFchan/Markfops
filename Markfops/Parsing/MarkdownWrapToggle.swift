import Foundation

/// Decides what Command-B, Command-I, and the other wrap commands do to the
/// source: wrap the selection in delimiters, or, when the selection already
/// sits inside a construct made by those delimiters, remove that construct's
/// delimiters. Shared by the monospace editor and formatted mode.
enum MarkdownWrapToggle {
    struct Edit: Equatable {
        /// Source range to replace.
        let range: NSRange
        let replacement: String
        /// Source selection to show afterwards.
        let selection: NSRange
    }

    static func edit(
        in text: NSString,
        sourceMap: MarkdownSourceMap,
        selection: NSRange,
        prefix: String,
        suffix: String
    ) -> Edit {
        if let kind = kind(forPrefix: prefix),
           let span = innermostSpan(kind: kind, containing: selection, in: sourceMap.span),
           let unwrap = unwrapEdit(for: span, selection: selection, in: text) {
            return unwrap
        }
        let selected = text.substring(with: selection)
        return Edit(
            range: selection,
            replacement: prefix + selected + suffix,
            selection: NSRange(
                location: selection.location + (prefix as NSString).length,
                length: selection.length
            )
        )
    }

    private static func kind(forPrefix prefix: String) -> MarkdownSourceMap.Kind? {
        switch prefix {
        case "**", "__": return .strong
        case "*", "_": return .emphasis
        case "`": return .codeSpan
        case "~~": return .strikethrough
        default: return nil
        }
    }

    /// The innermost content span of `kind` whose extent, delimiters included,
    /// contains the whole selection.
    private static func innermostSpan(
        kind: MarkdownSourceMap.Kind,
        containing selection: NSRange,
        in span: MarkdownSourceMap.Span
    ) -> MarkdownSourceMap.Span? {
        for child in span.children {
            if let found = innermostSpan(kind: kind, containing: selection, in: child) {
                return found
            }
        }
        guard span.role == .content, span.kind == kind else { return nil }
        let extent = extentWithDelimiters(of: span)
        guard extent.location <= selection.location,
              NSMaxRange(selection) <= NSMaxRange(extent) else { return nil }
        return span
    }

    private static func delimiters(of span: MarkdownSourceMap.Span) -> [NSRange] {
        span.children
            .filter { $0.role == .syntax && $0.range.length > 0 }
            .map(\.range)
            .sorted { $0.location < $1.location }
    }

    private static func extentWithDelimiters(of span: MarkdownSourceMap.Span) -> NSRange {
        delimiters(of: span).reduce(span.range) { NSUnionRange($0, $1) }
    }

    /// Replaces the construct with its content, delimiters removed, and maps
    /// the selection into the result. A selection point inside a delimiter
    /// lands where that delimiter was.
    private static func unwrapEdit(
        for span: MarkdownSourceMap.Span,
        selection: NSRange,
        in text: NSString
    ) -> Edit? {
        let delimiters = delimiters(of: span)
        guard !delimiters.isEmpty else { return nil }
        let extent = extentWithDelimiters(of: span)

        var replacement = ""
        var cursor = extent.location
        for delimiter in delimiters {
            if delimiter.location > cursor {
                replacement += text.substring(with: NSRange(location: cursor, length: delimiter.location - cursor))
            }
            cursor = max(cursor, NSMaxRange(delimiter))
        }
        if cursor < NSMaxRange(extent) {
            replacement += text.substring(with: NSRange(location: cursor, length: NSMaxRange(extent) - cursor))
        }

        func mapped(_ offset: Int) -> Int {
            var removed = 0
            for delimiter in delimiters {
                if NSMaxRange(delimiter) <= offset {
                    removed += delimiter.length
                } else if delimiter.location < offset {
                    removed += offset - delimiter.location
                }
            }
            return extent.location + (offset - extent.location) - removed
        }
        let start = mapped(selection.location)
        let end = mapped(NSMaxRange(selection))
        return Edit(
            range: extent,
            replacement: replacement,
            selection: NSRange(location: start, length: max(0, end - start))
        )
    }
}
