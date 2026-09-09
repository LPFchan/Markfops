import Foundation
import libcmark_gfm

private typealias CMarkNodePointer = UnsafeMutablePointer<cmark_node>

/// A disposable source map for the Markdown text currently held by a document.
///
/// The map keeps the cmark-gfm tree as nested spans and also keeps a compact
/// per-UTF-16-unit result for fast styling queries. Markdown remains the only
/// source of truth; callers should rebuild this value after a text revision.
struct MarkdownSourceMap {
    enum Role: Equatable {
        case syntax
        case content
    }

    enum TaskState: Equatable {
        case unchecked
        case checked
    }

    enum Kind: Equatable {
        case text
        case heading(level: Int)
        case paragraph
        case blockQuote
        case listItem(ordered: Bool, taskState: TaskState?)
        case codeBlock(fenced: Bool)
        case thematicBreak
        case htmlBlock
        case table
        case frontMatter
        case emphasis
        case strong
        case strikethrough
        case codeSpan
        case link
        case image
        case autolink
        case softBreak
        case lineBreak
        case inlineHTML
    }

    struct Span: Equatable {
        let range: NSRange
        let kind: Kind
        let role: Role
        let children: [Span]

        func span(at utf16Offset: Int) -> Span? {
            let childContains = children.contains { $0.contains(utf16Offset) }
            guard contains(utf16Offset) || childContains else { return nil }

            // Synthetic syntax spans are appended after cmark's child spans,
            // so reversing gives delimiters precedence at overlapping edges.
            for child in children.reversed() {
                if let result = child.span(at: utf16Offset) {
                    return result
                }
            }
            return contains(utf16Offset) ? self : nil
        }

        private func contains(_ utf16Offset: Int) -> Bool {
            range.length > 0 &&
                utf16Offset >= range.location &&
                utf16Offset < NSMaxRange(range)
        }
    }

    struct Run: Equatable {
        let range: NSRange
        let kind: Kind
        let role: Role
    }

    private struct CoverageEvent {
        let offset: Int
        let id: Int
        let depth: Int
        let kind: Kind
        let role: Role
        let starts: Bool
    }

    private let coverage: [Run]
    private let root: Span
    private let utf16Length: Int
    private let extractedHeadings: [HeadingNode]

    var span: Span { root }

    var headings: [HeadingNode] { extractedHeadings }

    var firstH1Title: String? {
        extractedHeadings.first(where: { $0.level == 1 })?.title
    }

    var firstH1Letter: String? {
        guard let title = firstH1Title, let first = title.first else { return nil }
        return String(first).uppercased()
    }

    /// Returns maximal, ordered runs clipped to the requested UTF-16 range.
    func runs(in requestedRange: NSRange) -> [Run] {
        guard requestedRange.length > 0, utf16Length > 0 else { return [] }

        let start = max(0, requestedRange.location)
        let requestedEnd = requestedRange.location + requestedRange.length
        let end = min(utf16Length, requestedEnd)
        guard start < end else { return [] }

        var clippedRuns: [Run] = []
        clippedRuns.reserveCapacity(coverage.count)
        for run in coverage {
            let runEnd = NSMaxRange(run.range)
            guard runEnd > start, run.range.location < end else {
                if run.range.location >= end { break }
                continue
            }
            let clippedStart = max(start, run.range.location)
            let clippedEnd = min(end, runEnd)
            guard clippedStart < clippedEnd else { continue }
            clippedRuns.append(Run(
                range: NSRange(location: clippedStart, length: clippedEnd - clippedStart),
                kind: run.kind,
                role: run.role
            ))
        }
        return clippedRuns
    }

    /// Returns the deepest parsed span containing a UTF-16 offset.
    func span(at utf16Offset: Int) -> Span? {
        root.span(at: utf16Offset)
    }

    static func parse(_ text: String) -> MarkdownSourceMap {
        let source = SourceText(text)
        let frontMatter = MarkdownFrontMatter.extract(from: text)
        let parserSource = frontMatter?.bodySource ?? text

        var topLevelBuilders: [SpanBuilder] = []
        var headingRecords: [(lineNumber: Int, level: Int, title: String)] = []

        cmark_gfm_core_extensions_ensure_registered()
        let options: Int32 = CMARK_OPT_UNSAFE | CMARK_OPT_SMART | CMARK_OPT_SOURCEPOS

        if let parser = cmark_parser_new(options) {
            defer { cmark_parser_free(parser) }

            let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
            for name in extensionNames {
                if let ext = cmark_find_syntax_extension(name) {
                    cmark_parser_attach_syntax_extension(parser, ext)
                }
            }

            if let cString = parserSource.cString(using: .utf8) {
                cmark_parser_feed(parser, cString, cString.count - 1)
            }

            if let document = cmark_parser_finish(parser) {
                defer { cmark_node_free(document) }

                if let iterator = cmark_iter_new(document) {
                    defer { cmark_iter_free(iterator) }

                    struct Frame {
                        let node: CMarkNodePointer
                        let builder: SpanBuilder?
                        var children: [SpanBuilder] = []
                    }

                    var stack: [Frame] = []
                    var event = cmark_iter_next(iterator)
                    while event != CMARK_EVENT_DONE {
                        guard let node = cmark_iter_get_node(iterator) else {
                            event = cmark_iter_next(iterator)
                            continue
                        }

                        switch event {
                        case CMARK_EVENT_ENTER:
                            let parent = stack.last?.node
                            let location = source.location(
                                startLine: Int(cmark_node_get_start_line(node)),
                                startColumn: Int(cmark_node_get_start_column(node)),
                                endLine: Int(cmark_node_get_end_line(node)),
                                endColumn: Int(cmark_node_get_end_column(node))
                            )
                            let parsedKind: Kind?
                            if let location {
                                parsedKind = Self.kind(
                                    for: node,
                                    parent: parent,
                                    location: location,
                                    source: source
                                )
                            } else {
                                parsedKind = nil
                            }
                            let builder: SpanBuilder?
                            if let parsedKind, let location {
                                builder = SpanBuilder(
                                    range: location.range,
                                    kind: parsedKind,
                                    location: location,
                                    literal: literal(of: node)
                                )
                            } else {
                                builder = nil
                            }
                            if isLeaf(node) {
                                if let builder {
                                    addSyntaxChildren(to: builder, source: source)
                                    if stack.isEmpty {
                                        topLevelBuilders.append(builder)
                                    } else {
                                        stack[stack.count - 1].children.append(builder)
                                    }
                                }
                            } else {
                                stack.append(Frame(node: node, builder: builder))
                            }

                        case CMARK_EVENT_EXIT:
                            guard let frame = stack.popLast() else {
                                event = cmark_iter_next(iterator)
                                continue
                            }
                            guard let builder = frame.builder else {
                                if !stack.isEmpty {
                                    stack[stack.count - 1].children.append(contentsOf: frame.children)
                                } else {
                                    topLevelBuilders.append(contentsOf: frame.children)
                                }
                                event = cmark_iter_next(iterator)
                                continue
                            }

                            builder.children = frame.children
                            addSyntaxChildren(to: builder, source: source)

                            if case let .heading(level) = builder.kind {
                                let title = plainText(in: builder)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !title.isEmpty {
                                    headingRecords.append((
                                        lineNumber: builder.location.startLine - 1,
                                        level: level,
                                        title: title
                                    ))
                                }
                            }

                            if stack.isEmpty {
                                topLevelBuilders.append(builder)
                            } else {
                                stack[stack.count - 1].children.append(builder)
                            }

                        default:
                            break
                        }

                        event = cmark_iter_next(iterator)
                    }
                }
            }
        }

        var childSpans = topLevelBuilders.map(\.span)
        if let frontMatter {
            childSpans.append(Span(
                range: frontMatter.range,
                kind: .frontMatter,
                role: .syntax,
                children: []
            ))
        }
        childSpans.sort { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.range.length > rhs.range.length
        }

        let root = Span(
            range: NSRange(location: 0, length: source.utf16Length),
            kind: .text,
            role: .content,
            children: childSpans
        )
        let coverage = coverageRuns(for: root)

        let headings = headingRecords
            .sorted { lhs, rhs in
                if lhs.lineNumber != rhs.lineNumber {
                    return lhs.lineNumber < rhs.lineNumber
                }
                return lhs.level < rhs.level
            }
            .map { HeadingNode(level: $0.level, title: $0.title, lineNumber: $0.lineNumber) }

        return MarkdownSourceMap(
            coverage: coverage,
            root: root,
            utf16Length: source.utf16Length,
            extractedHeadings: headings
        )
    }

    private init(
        coverage: [Run],
        root: Span,
        utf16Length: Int,
        extractedHeadings: [HeadingNode]
    ) {
        self.coverage = coverage
        self.root = root
        self.utf16Length = utf16Length
        self.extractedHeadings = extractedHeadings
    }

    private static func coverageRuns(for root: Span) -> [Run] {
        guard root.range.length > 0 else { return [] }

        var events: [CoverageEvent] = []
        events.reserveCapacity(2 * spanCount(in: root))
        var nextID = 0
        appendCoverageEvents(for: root, depth: 0, nextID: &nextID, to: &events)
        events.sort { lhs, rhs in
            if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
            if lhs.starts != rhs.starts { return !lhs.starts }
            return lhs.depth < rhs.depth
        }

        var active: [CoverageEvent] = []
        var runs: [Run] = []
        runs.reserveCapacity(events.count / 2)
        var cursor = root.range.location
        var eventIndex = 0

        while eventIndex < events.count {
            let offset = events[eventIndex].offset
            if cursor < offset, let innermost = active.max(by: isDeeper) {
                appendCoverageRun(
                    NSRange(location: cursor, length: offset - cursor),
                    kind: innermost.kind,
                    role: innermost.role,
                    to: &runs
                )
            }

            var nextIndex = eventIndex
            while nextIndex < events.count, events[nextIndex].offset == offset {
                nextIndex += 1
            }
            for event in events[eventIndex..<nextIndex] where !event.starts {
                active.removeAll { $0.id == event.id }
            }
            for event in events[eventIndex..<nextIndex] where event.starts {
                active.append(event)
            }
            cursor = offset
            eventIndex = nextIndex
        }

        return runs
    }

    private static func appendCoverageEvents(
        for span: Span,
        depth: Int,
        nextID: inout Int,
        to events: inout [CoverageEvent]
    ) {
        guard span.range.length > 0 else { return }
        let id = nextID
        nextID += 1
        events.append(CoverageEvent(
            offset: span.range.location,
            id: id,
            depth: depth,
            kind: span.kind,
            role: span.role,
            starts: true
        ))
        events.append(CoverageEvent(
            offset: NSMaxRange(span.range),
            id: id,
            depth: depth,
            kind: span.kind,
            role: span.role,
            starts: false
        ))
        for child in span.children {
            appendCoverageEvents(for: child, depth: depth + 1, nextID: &nextID, to: &events)
        }
    }

    private static func spanCount(in span: Span) -> Int {
        1 + span.children.reduce(into: 0) { count, child in
            count += spanCount(in: child)
        }
    }

    private static func isDeeper(_ lhs: CoverageEvent, _ rhs: CoverageEvent) -> Bool {
        if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
        return lhs.id < rhs.id
    }

    private static func appendCoverageRun(
        _ range: NSRange,
        kind: Kind,
        role: Role,
        to runs: inout [Run]
    ) {
        guard range.length > 0 else { return }
        if let last = runs.last,
           NSMaxRange(last.range) == range.location,
           last.kind == kind,
           last.role == role {
            runs[runs.count - 1] = Run(
                range: NSRange(location: last.range.location, length: last.range.length + range.length),
                kind: kind,
                role: role
            )
        } else {
            runs.append(Run(range: range, kind: kind, role: role))
        }
    }

    private static func kind(
        for node: CMarkNodePointer,
        parent: CMarkNodePointer?,
        location: SourceLocation,
        source: SourceText
    ) -> Kind? {
        let type = cmark_node_get_type(node)
        let typeString = String(cString: cmark_node_get_type_string(node))

        // GFM extensions register their own node type values at runtime rather
        // than exposing them as part of cmark's static enum. Their type names
        // are the stable discriminator that the renderer also receives.
        if typeString == "strikethrough" {
            return .strikethrough
        }
        if typeString == "autolink" {
            return .autolink
        }
        if typeString == "table" || typeString.hasPrefix("table_") {
            return .table
        }

        switch type {
        case CMARK_NODE_TEXT:
            return .text
        case CMARK_NODE_SOFTBREAK:
            return .softBreak
        case CMARK_NODE_LINEBREAK:
            return .lineBreak
        case CMARK_NODE_CODE:
            return .codeSpan
        case CMARK_NODE_HTML_INLINE:
            return .inlineHTML
        case CMARK_NODE_EMPH:
            return .emphasis
        case CMARK_NODE_STRONG:
            return .strong
        case CMARK_NODE_LINK:
            return source.isAutolink(location) ? .autolink : .link
        case CMARK_NODE_IMAGE:
            return .image
        case CMARK_NODE_BLOCK_QUOTE:
            return .blockQuote
        case CMARK_NODE_ITEM:
            let ordered = parent.map {
                cmark_node_get_list_type($0) == CMARK_ORDERED_LIST
            } ?? false
            let taskState: TaskState?
            if typeString == "tasklist" {
                taskState = cmark_gfm_extensions_get_tasklist_item_checked(node)
                    ? .checked
                    : .unchecked
            } else {
                taskState = nil
            }
            return .listItem(ordered: ordered, taskState: taskState)
        case CMARK_NODE_CODE_BLOCK:
            return .codeBlock(fenced: source.isFencedCodeBlock(location))
        case CMARK_NODE_HTML_BLOCK:
            return .htmlBlock
        case CMARK_NODE_PARAGRAPH:
            return .paragraph
        case CMARK_NODE_HEADING:
            return .heading(level: Int(cmark_node_get_heading_level(node)))
        case CMARK_NODE_THEMATIC_BREAK:
            return .thematicBreak
        case CMARK_NODE_CUSTOM_BLOCK:
            return nil
        case CMARK_NODE_CUSTOM_INLINE:
            return nil
        default:
            // Extension nodes that are not part of this slice remain transparent;
            // their parsed descendants still contribute their own spans.
            return nil
        }
    }

    private static func isLeaf(_ node: CMarkNodePointer) -> Bool {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_HTML_BLOCK,
             CMARK_NODE_THEMATIC_BREAK,
             CMARK_NODE_CODE_BLOCK,
             CMARK_NODE_TEXT,
             CMARK_NODE_SOFTBREAK,
             CMARK_NODE_LINEBREAK,
             CMARK_NODE_CODE,
             CMARK_NODE_HTML_INLINE:
            return true
        default:
            return false
        }
    }

    private static func literal(of node: CMarkNodePointer) -> String? {
        guard let pointer = cmark_node_get_literal(node) else { return nil }
        return String(cString: pointer)
    }

    private static func plainText(in builder: SpanBuilder) -> String {
        switch builder.kind {
        case .text, .codeSpan:
            return builder.literal ?? ""
        case .softBreak:
            return " "
        case .lineBreak:
            return "\n"
        case .inlineHTML, .htmlBlock:
            return ""
        default:
            return builder.children.map(plainText(in:)).joined()
        }
    }

    private static func addSyntaxChildren(to builder: SpanBuilder, source: SourceText) {
        switch builder.kind {
        case let .heading(level):
            addHeadingSyntax(to: builder, level: level, source: source)
        case .codeSpan:
            addCodeSpanSyntax(to: builder, source: source)
        case .emphasis, .strong, .strikethrough:
            addDelimiterSyntax(to: builder, source: source)
        case .link, .image:
            addLinkSyntax(to: builder, source: source)
        case .autolink:
            addAutolinkSyntax(to: builder, source: source)
        case .listItem:
            addListMarkerSyntax(to: builder, source: source)
        case .blockQuote:
            addBlockQuoteSyntax(to: builder, source: source)
        case let .codeBlock(fenced):
            if fenced {
                addFencedCodeSyntax(to: builder, source: source)
            }
        case .thematicBreak:
            addThematicBreakSyntax(to: builder, source: source)
        case .htmlBlock, .inlineHTML:
            builder.addSyntax(range: builder.range, kind: builder.kind)
        case .lineBreak:
            addLineBreakSyntax(to: builder, source: source)
        default:
            break
        }
    }

    private static func addHeadingSyntax(to builder: SpanBuilder, level: Int, source: SourceText) {
        guard builder.location.startLine == builder.location.endLine else {
            let line = source.line(builder.location.endLine)
            let start = line.startByte + line.leadingWhitespaceCount(in: source.bytes)
            let end = line.contentEnd(in: source.bytes)
            guard start < end else { return }
            let expected = level == 1 ? ascii("=") : ascii("-")
            guard line.isSetextUnderline(in: source.bytes, expected: expected) else { return }
            builder.addSyntax(utf8Start: start, utf8End: end, kind: builder.kind, source: source)
            return
        }

        let line = source.line(builder.location.startLine)
        var index = line.startByte
        while index < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[index]) {
            index += 1
        }
        let hashStart = index
        while index < line.contentEnd(in: source.bytes), source.bytes[index] == ascii("#") {
            index += 1
        }
        guard index > hashStart, index - hashStart <= 6 else { return }

        let afterHashes = index
        while index < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[index]) {
            index += 1
        }
        if index > afterHashes || afterHashes == line.contentEnd(in: source.bytes) {
            builder.addSyntax(utf8Start: hashStart, utf8End: index, kind: builder.kind, source: source)
        }

        var closingEnd = line.contentEnd(in: source.bytes)
        while closingEnd > line.startByte,
              source.isHorizontalWhitespace(source.bytes[closingEnd - 1]) {
            closingEnd -= 1
        }
        var closingStart = closingEnd
        while closingStart > line.startByte,
              source.bytes[closingStart - 1] == ascii("#") {
            closingStart -= 1
        }
        if closingStart < closingEnd,
           closingStart > line.startByte,
           source.isHorizontalWhitespace(source.bytes[closingStart - 1]) {
            builder.addSyntax(
                utf8Start: closingStart,
                utf8End: closingEnd,
                kind: builder.kind,
                source: source
            )
        }
    }

    private static func addCodeSpanSyntax(to builder: SpanBuilder, source: SourceText) {
        let openingEnd = builder.location.utf8Start
        var openingStart = openingEnd
        while openingStart > 0, source.bytes[openingStart - 1] == ascii("`") {
            openingStart -= 1
        }
        if openingStart < openingEnd {
            builder.addSyntax(
                utf8Start: openingStart,
                utf8End: openingEnd,
                kind: builder.kind,
                source: source
            )
        }

        let closingStart = builder.location.utf8End
        var closingEnd = closingStart
        while closingEnd < source.bytes.count, source.bytes[closingEnd] == ascii("`") {
            closingEnd += 1
        }
        if closingStart < closingEnd {
            builder.addSyntax(
                utf8Start: closingStart,
                utf8End: closingEnd,
                kind: builder.kind,
                source: source
            )
        }
    }

    private static func addDelimiterSyntax(to builder: SpanBuilder, source: SourceText) {
        let delimiter: UInt8
        let requiredLength: Int
        switch builder.kind {
        case .emphasis:
            delimiter = source.bytes[builder.location.utf8Start] == ascii("_")
                ? ascii("_")
                : ascii("*")
            requiredLength = 1
        case .strong:
            delimiter = source.bytes[builder.location.utf8Start] == ascii("_")
                ? ascii("_")
                : ascii("*")
            requiredLength = 2
        case .strikethrough:
            delimiter = ascii("~")
            requiredLength = 2
        default:
            return
        }

        var openingLength = 0
        while builder.location.utf8Start + openingLength < source.bytes.count,
              source.bytes[builder.location.utf8Start + openingLength] == delimiter {
            openingLength += 1
        }
        if openingLength >= requiredLength {
            builder.addSyntax(
                utf8Start: builder.location.utf8Start,
                utf8End: builder.location.utf8Start + requiredLength,
                kind: builder.kind,
                source: source
            )
        }

        var closingLength = 0
        var closingStart = builder.location.utf8End
        while closingStart > 0, source.bytes[closingStart - 1] == delimiter {
            closingStart -= 1
            closingLength += 1
        }
        if closingLength >= requiredLength {
            builder.addSyntax(
                utf8Start: builder.location.utf8End - requiredLength,
                utf8End: builder.location.utf8End,
                kind: builder.kind,
                source: source
            )
        }
    }

    private static func addLinkSyntax(to builder: SpanBuilder, source: SourceText) {
        let start = builder.location.utf8Start
        let end = builder.location.utf8End
        guard start < end else { return }

        var bracketStart = start
        if builder.kind == .image {
            guard source.bytes[start] == ascii("!") else { return }
            builder.addSyntax(utf8Start: start, utf8End: start + 1, kind: builder.kind, source: source)
            bracketStart += 1
        }
        guard bracketStart < end, source.bytes[bracketStart] == ascii("[") else { return }
        builder.addSyntax(utf8Start: bracketStart, utf8End: bracketStart + 1, kind: builder.kind, source: source)

        var index = bracketStart + 1
        var depth = 1
        var escaped = false
        var closingBracket: Int?
        while index < end {
            let byte = source.bytes[index]
            if escaped {
                escaped = false
            } else if byte == ascii("\\") {
                escaped = true
            } else if byte == ascii("[") {
                depth += 1
            } else if byte == ascii("]") {
                depth -= 1
                if depth == 0 {
                    closingBracket = index
                    break
                }
            }
            index += 1
        }

        guard let closingBracket else { return }
        builder.addSyntax(
            utf8Start: closingBracket,
            utf8End: closingBracket + 1,
            kind: builder.kind,
            source: source
        )

        var parenthesis = closingBracket + 1
        while parenthesis < end, source.isHorizontalWhitespace(source.bytes[parenthesis]) {
            parenthesis += 1
        }
        if parenthesis < end, source.bytes[parenthesis] == ascii("(") {
            builder.addSyntax(
                utf8Start: parenthesis,
                utf8End: end,
                kind: builder.kind,
                source: source
            )
        }
    }

    private static func addAutolinkSyntax(to builder: SpanBuilder, source: SourceText) {
        let start = builder.location.utf8Start
        let end = builder.location.utf8End
        guard end - start >= 2 else { return }
        builder.addSyntax(utf8Start: start, utf8End: start + 1, kind: builder.kind, source: source)
        builder.addSyntax(utf8Start: end - 1, utf8End: end, kind: builder.kind, source: source)
    }

    private static func addListMarkerSyntax(to builder: SpanBuilder, source: SourceText) {
        let line = source.line(builder.location.startLine)
        var marker = line.startByte
        while marker < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[marker]) {
            marker += 1
        }
        guard marker < line.contentEnd(in: source.bytes) else { return }

        let ordered: Bool
        if case let .listItem(isOrdered, _) = builder.kind {
            ordered = isOrdered
        } else {
            return
        }

        var markerEnd = marker
        if ordered {
            while markerEnd < line.contentEnd(in: source.bytes),
                  source.bytes[markerEnd] >= ascii("0"),
                  source.bytes[markerEnd] <= ascii("9") {
                markerEnd += 1
            }
            guard markerEnd > marker,
                  markerEnd < line.contentEnd(in: source.bytes),
                  source.bytes[markerEnd] == ascii(".") || source.bytes[markerEnd] == ascii(")") else {
                return
            }
            markerEnd += 1
        } else {
            guard source.bytes[marker] == ascii("-") ||
                    source.bytes[marker] == ascii("*") ||
                    source.bytes[marker] == ascii("+") else {
                return
            }
            markerEnd += 1
        }
        while markerEnd < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[markerEnd]) {
            markerEnd += 1
        }

        if case .listItem(_, .some) = builder.kind,
           markerEnd + 2 < line.contentEnd(in: source.bytes),
           source.bytes[markerEnd] == ascii("["),
           source.bytes[markerEnd + 2] == ascii("]"),
           (source.bytes[markerEnd + 1] == ascii(" ") ||
                source.bytes[markerEnd + 1] == ascii("x") ||
                source.bytes[markerEnd + 1] == ascii("X")) {
            markerEnd += 3
            while markerEnd < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[markerEnd]) {
                markerEnd += 1
            }
        }

        builder.addSyntax(utf8Start: marker, utf8End: markerEnd, kind: builder.kind, source: source)
    }

    private static func addBlockQuoteSyntax(to builder: SpanBuilder, source: SourceText) {
        let firstLine = builder.location.startLine
        let lastLine = builder.location.endLine
        guard firstLine <= lastLine else { return }

        for lineNumber in firstLine...lastLine {
            let line = source.line(lineNumber)
            var index = line.startByte
            while index < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[index]) {
                index += 1
            }
            while index < line.contentEnd(in: source.bytes), source.bytes[index] == ascii(">") {
                let markerEnd = min(line.contentEnd(in: source.bytes), index + 1)
                builder.addSyntax(utf8Start: index, utf8End: markerEnd, kind: builder.kind, source: source)
                index = markerEnd
                if index < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[index]) {
                    builder.addSyntax(utf8Start: index, utf8End: index + 1, kind: builder.kind, source: source)
                    index += 1
                }
                while index < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[index]) {
                    index += 1
                }
            }
        }
    }

    private static func addFencedCodeSyntax(to builder: SpanBuilder, source: SourceText) {
        let openingLine = source.line(builder.location.startLine)
        var fenceStart = openingLine.startByte
        while fenceStart < openingLine.contentEnd(in: source.bytes),
              source.isHorizontalWhitespace(source.bytes[fenceStart]) {
            fenceStart += 1
        }
        guard fenceStart < openingLine.contentEnd(in: source.bytes),
              source.bytes[fenceStart] == ascii("`") || source.bytes[fenceStart] == ascii("~") else {
            return
        }

        let fenceCharacter = source.bytes[fenceStart]
        var fenceLength = fenceStart
        while fenceLength < openingLine.contentEnd(in: source.bytes),
              source.bytes[fenceLength] == fenceCharacter {
            fenceLength += 1
        }
        guard fenceLength - fenceStart >= 3 else { return }
        builder.addSyntax(
            utf8Start: fenceStart,
            utf8End: openingLine.contentEnd(in: source.bytes),
            kind: builder.kind,
            source: source
        )

        if builder.location.startLine + 1 <= builder.location.endLine {
            for lineNumber in (builder.location.startLine + 1)...builder.location.endLine {
                let line = source.line(lineNumber)
                var start = line.startByte
                while start < line.contentEnd(in: source.bytes), source.isHorizontalWhitespace(source.bytes[start]) {
                    start += 1
                }
                guard start < line.contentEnd(in: source.bytes), source.bytes[start] == fenceCharacter else { continue }

                var runEnd = start
                while runEnd < line.contentEnd(in: source.bytes), source.bytes[runEnd] == fenceCharacter {
                    runEnd += 1
                }
                guard runEnd - start >= fenceLength - fenceStart else { continue }
                builder.addSyntax(
                    utf8Start: start,
                    utf8End: line.contentEnd(in: source.bytes),
                    kind: builder.kind,
                    source: source
                )
            }
        }
    }

    private static func addThematicBreakSyntax(to builder: SpanBuilder, source: SourceText) {
        let line = source.line(builder.location.startLine)
        let start = line.startByte
        let end = line.contentEnd(in: source.bytes)
        guard start < end else { return }
        builder.addSyntax(utf8Start: start, utf8End: end, kind: builder.kind, source: source)
    }

    private static func addLineBreakSyntax(to builder: SpanBuilder, source: SourceText) {
        let start = builder.location.utf8Start
        guard start > 0, source.bytes[start - 1] == ascii("\\") else { return }
        builder.addSyntax(utf8Start: start - 1, utf8End: start, kind: builder.kind, source: source)
    }
}

private final class SpanBuilder {
    let range: NSRange
    let kind: MarkdownSourceMap.Kind
    let location: SourceLocation
    let literal: String?
    let isSyntax: Bool
    var children: [SpanBuilder] = []

    init(
        range: NSRange,
        kind: MarkdownSourceMap.Kind,
        location: SourceLocation,
        literal: String?,
        isSyntax: Bool = false
    ) {
        self.range = range
        self.kind = kind
        self.location = location
        self.literal = literal
        self.isSyntax = isSyntax
    }

    func addSyntax(utf8Start: Int, utf8End: Int, kind: MarkdownSourceMap.Kind, source: SourceText) {
        guard let range = source.range(utf8Start: utf8Start, utf8End: utf8End) else { return }
        addSyntax(range: range, kind: kind)
    }

    func addSyntax(range: NSRange, kind: MarkdownSourceMap.Kind) {
        guard range.length > 0 else { return }
        children.append(SpanBuilder(
            range: range,
            kind: kind,
            location: SourceLocation(
                range: range,
                startLine: location.startLine,
                endLine: location.endLine,
                utf8Start: 0,
                utf8End: 0
            ),
            literal: nil,
            isSyntax: true
        ))
    }

    var span: MarkdownSourceMap.Span {
        MarkdownSourceMap.Span(
            range: range,
            kind: kind,
            role: isSyntax ? .syntax : .content,
            children: children.map(\.span)
        )
    }

}

private struct SourceLocation {
    let range: NSRange
    let startLine: Int
    let endLine: Int
    let utf8Start: Int
    let utf8End: Int
}

private struct SourceText {
    struct Line {
        let startByte: Int
        let endByte: Int
        let startUTF16: Int
        let endUTF16: Int

        func contentEnd(in bytes: Data) -> Int {
            var end = endByte
            if end > startByte, bytes[end - 1] == 0x0D {
                end -= 1
            }
            return end
        }

        func leadingWhitespaceCount(in bytes: Data) -> Int {
            var index = startByte
            let end = contentEnd(in: bytes)
            while index < end, bytes[index] == 0x20 || bytes[index] == 0x09 {
                index += 1
            }
            return index - startByte
        }

        func isSetextUnderline(in bytes: Data, expected: UInt8) -> Bool {
            let start = startByte + leadingWhitespaceCount(in: bytes)
            let end = contentEnd(in: bytes)
            guard start < end else { return false }
            for byte in bytes[start..<end] where byte != expected {
                return false
            }
            return true
        }
    }

    let bytes: Data
    let utf8ToUTF16: [Int]?
    let lines: [Line]
    let utf16Length: Int

    init(_ text: String) {
        let bytes = text.data(using: .utf8) ?? Data()
        var lineStarts: [(byte: Int, utf16: Int)] = [(0, 0)]
        let utf8ToUTF16: [Int]?
        let utf16Offset: Int

        if bytes.allSatisfy({ $0 < 0x80 }) {
            // Most editor documents are ASCII-heavy. For this common case,
            // UTF-8 and UTF-16 offsets are identical and the mapping is free
            // of per-scalar bookkeeping.
            utf8ToUTF16 = nil
            utf16Offset = bytes.count
            for byteOffset in bytes.indices where bytes[byteOffset] == 0x0A {
                let nextOffset = byteOffset + 1
                lineStarts.append((nextOffset, nextOffset))
            }
        } else {
            var mapping = Array(repeating: 0, count: bytes.count + 1)
            var byteOffset = 0
            var currentUTF16Offset = 0

            for scalar in text.unicodeScalars {
                let scalarUTF8Length = scalar.utf8.count
                let scalarUTF16Length = scalar.utf16.count
                for offset in 0..<scalarUTF8Length {
                    mapping[byteOffset + offset] = currentUTF16Offset
                }
                byteOffset += scalarUTF8Length
                currentUTF16Offset += scalarUTF16Length
                mapping[byteOffset] = currentUTF16Offset
                if scalar.value == 0x0A {
                    lineStarts.append((byteOffset, currentUTF16Offset))
                }
            }
            utf8ToUTF16 = mapping
            utf16Offset = currentUTF16Offset
        }

        var lines: [Line] = []
        lines.reserveCapacity(lineStarts.count)
        for index in lineStarts.indices {
            let start = lineStarts[index]
            let next = index + 1 < lineStarts.count ? lineStarts[index + 1] : nil
            let endByte = next.map { $0.byte - 1 } ?? bytes.count
            let endUTF16 = next.map { $0.utf16 - 1 } ?? utf16Offset
            lines.append(Line(
                startByte: start.byte,
                endByte: max(start.byte, endByte),
                startUTF16: start.utf16,
                endUTF16: max(start.utf16, endUTF16)
            ))
        }

        self.bytes = bytes
        self.utf8ToUTF16 = utf8ToUTF16
        self.lines = lines
        self.utf16Length = utf16Offset
    }

    func line(_ oneBasedLine: Int) -> Line {
        let index = min(max(oneBasedLine - 1, 0), max(lines.count - 1, 0))
        return lines[index]
    }

    func location(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) -> SourceLocation? {
        guard startLine >= 1, endLine >= startLine,
              startLine <= lines.count, endLine <= lines.count,
              startColumn >= 1, endColumn >= 0 else {
            return nil
        }

        // cmark reports line N, column 0 for a block whose source ends at the
        // start of line N. This happens when a block is finalized just before a
        // blank line, including setext headings, list items, and thematic
        // breaks. Treat such a block as ending at the end of line N - 1 so its
        // last line (for a setext heading, the underline) stays inside the span.
        let resolvedEndLine: Int
        if endColumn == 0 {
            guard endLine > startLine else { return nil }
            resolvedEndLine = endLine - 1
        } else {
            resolvedEndLine = endLine
        }

        let startLineInfo = line(startLine)
        let endLineInfo = line(resolvedEndLine)
        let startByte = min(startLineInfo.endByte, startLineInfo.startByte + startColumn - 1)
        let endByte = endColumn == 0
            ? endLineInfo.contentEnd(in: bytes)
            : min(endLineInfo.endByte, endLineInfo.startByte + endColumn)
        guard startByte <= endByte else { return nil }

        let startUTF16 = utf16Offset(forUTF8Byte: startByte)
        let endUTF16 = utf16Offset(forUTF8Byte: endByte)
        return SourceLocation(
            range: NSRange(location: startUTF16, length: max(0, endUTF16 - startUTF16)),
            startLine: startLine,
            endLine: resolvedEndLine,
            utf8Start: startByte,
            utf8End: endByte
        )
    }

    func range(utf8Start: Int, utf8End: Int) -> NSRange? {
        guard utf8Start >= 0, utf8End >= utf8Start,
              utf8Start <= bytes.count, utf8End <= bytes.count else {
            return nil
        }
        return NSRange(
            location: utf16Offset(forUTF8Byte: utf8Start),
            length: utf16Offset(forUTF8Byte: utf8End) - utf16Offset(forUTF8Byte: utf8Start)
        )
    }

    private func utf16Offset(forUTF8Byte byteOffset: Int) -> Int {
        utf8ToUTF16?[byteOffset] ?? byteOffset
    }

    func isHorizontalWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09
    }

    func isAutolink(_ location: SourceLocation) -> Bool {
        guard location.utf8End - location.utf8Start >= 2 else { return false }
        if bytes[location.utf8Start] == ascii("<") &&
            bytes[location.utf8End - 1] == ascii(">") {
            return true
        }

        // GFM's bare URL/email autolinks are represented as ordinary LINK
        // nodes. A parsed Markdown link always starts with '[' (or '![', which
        // is handled by the IMAGE node), so this local boundary check separates
        // the two without scanning the document.
        return bytes[location.utf8Start] != ascii("[") &&
            bytes[location.utf8Start] != ascii("!")
    }

    func isFencedCodeBlock(_ location: SourceLocation) -> Bool {
        let line = line(location.startLine)
        var index = line.startByte
        while index < line.contentEnd(in: bytes), isHorizontalWhitespace(bytes[index]) {
            index += 1
        }
        guard index < line.contentEnd(in: bytes), bytes[index] == ascii("`") || bytes[index] == ascii("~") else {
            return false
        }
        let character = bytes[index]
        var length = 0
        while index + length < line.contentEnd(in: bytes), bytes[index + length] == character {
            length += 1
        }
        return length >= 3
    }
}

private func ascii(_ character: Character) -> UInt8 {
    Array(String(character).utf8)[0]
}
