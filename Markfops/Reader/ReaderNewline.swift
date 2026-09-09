import Foundation

/// Decides what the Enter key inserts into the source from formatted mode.
enum ReaderNewline {
    /// A lone newline inside a paragraph is a soft break, which the reader
    /// shows as a space. Enter in prose therefore starts a new paragraph. Inside
    /// constructs where a line has its own meaning (code, list items, quotes,
    /// tables, HTML blocks, front matter) a single newline is inserted; list
    /// continuation and quote prefixes are a later slice.
    static func replacement(in sourceMap: MarkdownSourceMap, sourceOffset: Int) -> String {
        keepsSingleNewline(in: sourceMap.span, offset: sourceOffset) ? "\n" : "\n\n"
    }

    private static func keepsSingleNewline(in span: MarkdownSourceMap.Span, offset: Int) -> Bool {
        guard span.range.location <= offset,
              offset <= NSMaxRange(span.range) else { return false }
        // Front matter is a syntax-role span; every other block is content.
        if span.kind == .frontMatter { return true }
        guard span.role == .content else { return false }
        switch span.kind {
        case .listItem, .blockQuote, .codeBlock, .table, .htmlBlock:
            return true
        default:
            break
        }
        return span.children.contains { keepsSingleNewline(in: $0, offset: offset) }
    }
}
