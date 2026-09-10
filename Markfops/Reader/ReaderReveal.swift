import Foundation

/// Decides which source syntax the reader shows in place around the text cursor.
enum ReaderReveal {
    /// The source range whose hidden syntax should be visible for a cursor at
    /// `sourceCursor`: every inline construct (emphasis, strong, strikethrough,
    /// code span, link, autolink, image) that contains the cursor, including at
    /// its end so a cursor right after a bold word reveals it, unioned with the
    /// block the cursor sits in when that block has syntax of its own: a
    /// heading (its `#` marks), a fenced code block (both fence lines), a
    /// block quote (every `>` marker), or the innermost list item (its
    /// marker). Nested constructs reveal together through the outermost one;
    /// a code block inside a quote reveals both. Other blocks, including
    /// indented code, reveal nothing.
    static func range(in sourceMap: MarkdownSourceMap, sourceCursor: Int) -> NSRange? {
        var result: NSRange?
        collect(in: sourceMap.span, cursor: sourceCursor, into: &result)
        return result
    }

    private static func collect(
        in span: MarkdownSourceMap.Span,
        cursor: Int,
        into result: inout NSRange?
    ) {
        guard span.role == .content,
              span.range.location <= cursor,
              cursor <= NSMaxRange(span.range) else { return }

        switch span.kind {
        case .emphasis, .strong, .strikethrough, .codeSpan, .link, .autolink, .image:
            union(spanRangeWithDelimiters(span), into: &result)
            return
        case .heading, .blockQuote:
            union(span.range, into: &result)
        case .codeBlock(fenced: true):
            union(spanRangeWithDelimiters(span), into: &result)
            return
        case .listItem:
            // The innermost item owns the cursor: a parent's bullet stays a
            // bullet while a nested item is being edited.
            if !hasNestedItem(in: span, containing: cursor) {
                for child in span.children where child.role == .syntax && child.kind == span.kind {
                    union(child.range, into: &result)
                }
            }
        default:
            break
        }
        for child in span.children {
            collect(in: child, cursor: cursor, into: &result)
        }
    }

    private static func hasNestedItem(in span: MarkdownSourceMap.Span, containing cursor: Int) -> Bool {
        span.children.contains { child in
            guard child.role == .content,
                  child.range.location <= cursor,
                  cursor <= NSMaxRange(child.range) else { return false }
            if case .listItem = child.kind { return true }
            return hasNestedItem(in: child, containing: cursor)
        }
    }

    /// A code span's node range excludes its backticks, which sit in syntax
    /// children just outside it. The revealed range must cover them too. A
    /// fenced block's range already holds its fences; the union is a no-op there.
    private static func spanRangeWithDelimiters(_ span: MarkdownSourceMap.Span) -> NSRange {
        var range = span.range
        for child in span.children where child.role == .syntax {
            range = NSUnionRange(range, child.range)
        }
        return range
    }

    private static func union(_ range: NSRange, into result: inout NSRange?) {
        if let current = result {
            result = NSUnionRange(current, range)
        } else {
            result = range
        }
    }
}
