import Foundation

/// Decides what the Enter key does to the source from formatted mode.
enum ReaderNewline {
    /// The edit Enter makes with `selection` in `text`.
    ///
    /// A lone newline inside a paragraph is a soft break, which the reader
    /// shows as a space, so Enter in prose starts a new paragraph. Inside
    /// code, tables, HTML blocks, and front matter it inserts a single
    /// newline. Inside a list item it starts the next item: the same bullet,
    /// the next number with the same delimiter, or an unchecked task box,
    /// behind the item's indent and any quote markers around it. On an item
    /// with no content the marker is removed instead, which ends the list;
    /// a nested empty item outdents one level. Inside a block quote the
    /// line's quote markers continue on the new line, and a line that is
    /// only markers loses them. A caret inside a line's markers acts at the
    /// start of the line's content.
    ///
    /// The edit carries no kept text: the selection, if any, is replaced.
    static func edit(in text: NSString, sourceMap: MarkdownSourceMap, selection: NSRange) -> MarkdownSourceEdit {
        let selection = clamped(selection, to: text.length)
        let chain = blockChain(at: selection.location, in: sourceMap.span)
        for (index, block) in chain.enumerated().reversed() {
            switch block.kind {
            case .codeBlock, .table, .htmlBlock, .frontMatter:
                return plain("\n", replacing: selection)
            case .listItem:
                let parent = index > 0 ? chain[index - 1] : nil
                if let edit = listEdit(item: block, parent: parent, selection: selection, in: text) {
                    return edit
                }
            case .blockQuote:
                if let edit = quoteEdit(quote: block, selection: selection, in: text) {
                    return edit
                }
            default:
                break
            }
        }
        return plain("\n\n", replacing: selection)
    }

    /// Whether an Enter edit changes what block its line is: it writes a
    /// prefix (anything besides newlines) or removes one (deletes without
    /// inserting). Those edits animate like a heading change; a plain
    /// newline stays instant.
    static func changesBlock(_ edit: MarkdownSourceEdit) -> Bool {
        if edit.replacement.isEmpty { return edit.range.length > 0 }
        return edit.replacement.contains { !$0.isNewline }
    }

    // MARK: - Blocks

    private static func plain(_ replacement: String, replacing selection: NSRange) -> MarkdownSourceEdit {
        MarkdownSourceEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0),
            kept: []
        )
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let end = max(location, min(NSMaxRange(range), length))
        return NSRange(location: location, length: end - location)
    }

    /// The blocks holding `offset`, outermost first. A block holds the
    /// offset at its end too, so a caret at the end of an item belongs to
    /// it; where two blocks meet, the later one wins.
    private static func blockChain(at offset: Int, in root: MarkdownSourceMap.Span) -> [MarkdownSourceMap.Span] {
        var chain: [MarkdownSourceMap.Span] = []
        var current = root
        while let next = current.children.last(where: {
            ($0.role == .content || $0.kind == .frontMatter)
                && isBlock($0.kind)
                && $0.range.location <= offset
                && offset <= NSMaxRange($0.range)
        }) {
            chain.append(next)
            current = next
        }
        return chain
    }

    private static func isBlock(_ kind: MarkdownSourceMap.Kind) -> Bool {
        switch kind {
        case .heading, .paragraph, .blockQuote, .listItem, .codeBlock,
             .thematicBreak, .htmlBlock, .table, .frontMatter:
            return true
        default:
            return false
        }
    }

    // MARK: - List items

    private static func listEdit(
        item: MarkdownSourceMap.Span,
        parent: MarkdownSourceMap.Span?,
        selection: NSRange,
        in text: NSString
    ) -> MarkdownSourceEdit? {
        guard let marker = markerRange(of: item) else { return nil }
        let contentStart = NSMaxRange(marker)
        let range = snapped(selection, toStartAt: contentStart)
        let contentEnd = max(contentStart, NSMaxRange(item.range))
        let content = text.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
        let isEmpty = content.allSatisfy { $0 == " " || $0 == "\t" || $0.isNewline }

        if isEmpty {
            let removed: NSRange
            if let parent, case .listItem = parent.kind,
               let parentMarker = markerRange(of: parent),
               case let outdent = indentWidth(before: marker.location, in: text) - indentWidth(before: parentMarker.location, in: text),
               outdent > 0 {
                removed = NSRange(location: marker.location - outdent, length: outdent)
            } else {
                removed = marker
            }
            return MarkdownSourceEdit(
                range: removed,
                replacement: "",
                selection: NSRange(location: range.location - removed.length, length: 0),
                kept: []
            )
        }

        let line = lineContent(at: marker.location, in: text)
        let indent = continuation(
            of: prefixTokens(in: NSRange(location: line.location, length: marker.location - line.location), of: text),
            in: text
        )
        let replacement = "\n" + indent + nextMarker(after: text.substring(with: marker))
        return MarkdownSourceEdit(
            range: range,
            replacement: replacement,
            selection: NSRange(location: range.location + (replacement as NSString).length, length: 0),
            kept: []
        )
    }

    /// The item's marker run: the bullet or number, the whitespace binding it
    /// to the content, and a task box when the item has one.
    private static func markerRange(of item: MarkdownSourceMap.Span) -> NSRange? {
        item.children
            .filter { $0.role == .syntax && $0.kind == item.kind }
            .map(\.range)
            .min { $0.location < $1.location }
    }

    /// The marker that follows `marker` in its list: the same bullet, or the
    /// next number with the same delimiter, one space, and an unchecked box
    /// when the marker has a task box.
    static func nextMarker(after marker: String) -> String {
        var head = marker.trimmingCharacters(in: .whitespaces)
        let isTask = head.hasSuffix("]")
        if isTask, let box = head.lastIndex(of: "[") {
            head = head[..<box].trimmingCharacters(in: .whitespaces)
        }
        var next: String
        if let first = head.first, "-*+".contains(first) {
            next = String(first)
        } else if let delimiter = head.last, delimiter == "." || delimiter == ")",
                  let number = Int(head.dropLast()) {
            next = "\(number + 1)\(delimiter)"
        } else {
            next = "-"
        }
        next += " "
        if isTask { next += "[ ] " }
        return next
    }

    /// Width of the whitespace run ending at `offset` on its line.
    private static func indentWidth(before offset: Int, in text: NSString) -> Int {
        var start = offset
        while start > 0, isHorizontalSpace(text.character(at: start - 1)) {
            start -= 1
        }
        return offset - start
    }

    // MARK: - Block quotes

    private static func quoteEdit(
        quote: MarkdownSourceMap.Span,
        selection: NSRange,
        in text: NSString
    ) -> MarkdownSourceEdit? {
        let caretLine = lineContent(at: selection.location, in: text)
        let caretTokens = prefixTokens(in: caretLine, of: text)
        if let last = caretTokens.lastIndex(where: { if case .quote = $0 { return true } else { return false } }) {
            let markers = caretTokens[...last]
            let contentStart = NSMaxRange(caretTokens[last].range)
            let range = snapped(selection, toStartAt: contentStart)
            let tail = text.substring(with: NSRange(location: contentStart, length: NSMaxRange(caretLine) - contentStart))
            if tail.allSatisfy({ isHorizontalSpace($0.utf16.first ?? 0) }),
               let firstQuote = markers.first(where: { if case .quote = $0 { return true } else { return false } }) {
                let removed = NSRange(location: firstQuote.range.location, length: NSMaxRange(caretLine) - firstQuote.range.location)
                return MarkdownSourceEdit(
                    range: removed,
                    replacement: "",
                    selection: NSRange(location: removed.location, length: 0),
                    kept: []
                )
            }
            return continuationEdit(prefix: continuation(of: Array(markers), in: text), replacing: range)
        }

        // A lazy continuation line has no markers of its own; the quote's
        // first line has them.
        let firstLine = lineContent(at: quote.range.location, in: text)
        let tokens = prefixTokens(in: firstLine, of: text)
        guard let last = tokens.lastIndex(where: { if case .quote = $0 { return true } else { return false } }) else {
            return nil
        }
        return continuationEdit(prefix: continuation(of: Array(tokens[...last]), in: text), replacing: selection)
    }

    private static func continuationEdit(prefix: String, replacing range: NSRange) -> MarkdownSourceEdit {
        let replacement = "\n" + prefix
        return MarkdownSourceEdit(
            range: range,
            replacement: replacement,
            selection: NSRange(location: range.location + (replacement as NSString).length, length: 0),
            kept: []
        )
    }

    // MARK: - Line prefixes

    /// One piece of a line's leading block syntax.
    private enum PrefixToken {
        case whitespace(NSRange)
        /// A `>` and the one space that may follow it.
        case quote(NSRange)
        /// A bullet or number, its whitespace, and a task box when present.
        case marker(NSRange)

        var range: NSRange {
            switch self {
            case let .whitespace(range), let .quote(range), let .marker(range):
                return range
            }
        }
    }

    /// The leading block syntax of `line`, in order, up to the first
    /// character that is content.
    private static func prefixTokens(in line: NSRange, of text: NSString) -> [PrefixToken] {
        var tokens: [PrefixToken] = []
        var index = line.location
        let end = NSMaxRange(line)
        func character(_ at: Int) -> unichar? { at < end ? text.character(at: at) : nil }
        func skipSpaces() {
            while let c = character(index), isHorizontalSpace(c) { index += 1 }
        }
        while let c = character(index) {
            let start = index
            if isHorizontalSpace(c) {
                skipSpaces()
                tokens.append(.whitespace(NSRange(location: start, length: index - start)))
            } else if c == 0x3E { // >
                index += 1
                if let next = character(index), isHorizontalSpace(next) { index += 1 }
                tokens.append(.quote(NSRange(location: start, length: index - start)))
            } else if let markerEnd = listMarkerEnd(at: index, before: end, in: text) {
                index = markerEnd
                tokens.append(.marker(NSRange(location: start, length: index - start)))
            } else {
                break
            }
        }
        return tokens
    }

    /// The end of a list marker run starting at `offset`, or nil when the
    /// character there does not start one.
    private static func listMarkerEnd(at offset: Int, before end: Int, in text: NSString) -> Int? {
        var index = offset
        let c = text.character(at: index)
        if c == 0x2D || c == 0x2A || c == 0x2B { // - * +
            index += 1
        } else if c >= 0x30, c <= 0x39 {
            while index < end, text.character(at: index) >= 0x30, text.character(at: index) <= 0x39 { index += 1 }
            guard index - offset <= 9, index < end,
                  text.character(at: index) == 0x2E || text.character(at: index) == 0x29 else { return nil } // . )
            index += 1
        } else {
            return nil
        }
        guard index == end || isHorizontalSpace(text.character(at: index)) else { return nil }
        while index < end, isHorizontalSpace(text.character(at: index)) { index += 1 }
        if index + 3 <= end,
           text.character(at: index) == 0x5B, // [
           text.character(at: index + 2) == 0x5D, // ]
           [0x20, 0x78, 0x58].contains(text.character(at: index + 1)), // space x X
           index + 3 == end || isHorizontalSpace(text.character(at: index + 3)) {
            index += 3
            while index < end, isHorizontalSpace(text.character(at: index)) { index += 1 }
        }
        return index
    }

    /// The prefix a new line needs to stay inside the same blocks as
    /// `tokens`: whitespace as written, `> ` for each quote marker, and
    /// spaces in place of a list marker so the line continues its item
    /// without starting another.
    private static func continuation(of tokens: [PrefixToken], in text: NSString) -> String {
        tokens.map { token in
            switch token {
            case let .whitespace(range):
                return text.substring(with: range)
            case .quote:
                return "> "
            case let .marker(range):
                return String(repeating: " ", count: range.length)
            }
        }.joined()
    }

    /// `selection` moved so it starts no earlier than `start`.
    private static func snapped(_ selection: NSRange, toStartAt start: Int) -> NSRange {
        let location = max(selection.location, start)
        return NSRange(location: location, length: max(0, NSMaxRange(selection) - location))
    }

    private static func lineContent(at offset: Int, in text: NSString) -> NSRange {
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    private static func isHorizontalSpace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }
}
