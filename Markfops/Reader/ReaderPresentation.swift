import AppKit
import Foundation

struct ReaderTheme {
    var bodyFontSize: CGFloat
    var bodyColor: NSColor
    var backgroundColor: NSColor
    var secondaryColor: NSColor
    var linkColor: NSColor
    var codeBackgroundColor: NSColor
    var separatorColor: NSColor
    var contentInsets: NSEdgeInsets

    static var `default`: ReaderTheme {
        ReaderTheme(
            bodyFontSize: 16,
            bodyColor: .textColor,
            backgroundColor: .textBackgroundColor,
            secondaryColor: .secondaryLabelColor,
            linkColor: .linkColor,
            codeBackgroundColor: .controlBackgroundColor,
            separatorColor: .separatorColor,
            contentInsets: NSEdgeInsets(top: 40, left: 32, bottom: 80, right: 32)
        )
    }
}

struct ReaderOffsetMap {
    struct Record: Equatable {
        let sourceRange: NSRange
        let readerRange: NSRange
        let kind: MarkdownSourceMap.Kind
        let role: MarkdownSourceMap.Role
        let isSubstitution: Bool
    }

    let records: [Record]
    private let sourceToReader: [Int]
    private let readerToSource: [Int]
    private let sourceLineStarts: [Int]
    private let sourceLength: Int
    private let readerLength: Int

    init(
        records: [Record],
        sourceToReader: [Int],
        readerToSource: [Int],
        sourceLineStarts: [Int],
        sourceLength: Int,
        readerLength: Int
    ) {
        self.records = records
        self.sourceToReader = sourceToReader
        self.readerToSource = readerToSource
        self.sourceLineStarts = sourceLineStarts
        self.sourceLength = sourceLength
        self.readerLength = readerLength
    }

    /// Maps a source UTF-16 boundary to the nearest reader boundary. Source
    /// syntax that is hidden by the reader points at the next visible position.
    func readerOffset(forSourceOffset offset: Int) -> Int {
        guard !sourceToReader.isEmpty else { return 0 }
        let bounded = max(0, min(offset, sourceLength))
        return max(0, min(sourceToReader[bounded], readerLength))
    }

    /// Maps a reader UTF-16 boundary back to the nearest source boundary.
    func sourceOffset(forReaderOffset offset: Int) -> Int {
        guard !readerToSource.isEmpty else { return 0 }
        let bounded = max(0, min(offset, readerLength))
        return max(0, min(readerToSource[bounded], sourceLength))
    }

    /// Returns the reader range corresponding to one zero-based source line.
    /// Hidden leading syntax therefore maps to the first visible content on the line.
    func readerRange(forSourceLine lineNumber: Int) -> NSRange? {
        guard lineNumber >= 0, lineNumber < sourceLineStarts.count else { return nil }

        let sourceStart = sourceLineStarts[lineNumber]
        let sourceEnd: Int
        if lineNumber + 1 < sourceLineStarts.count {
            let nextLineStart = sourceLineStarts[lineNumber + 1]
            sourceEnd = nextLineStart > sourceStart ? nextLineStart - 1 : nextLineStart
        } else {
            sourceEnd = sourceLength
        }

        let readerStart = readerOffset(forSourceOffset: sourceStart)
        let readerEnd = readerOffset(forSourceOffset: max(sourceStart, sourceEnd))
        return NSRange(
            location: min(readerStart, readerEnd),
            length: abs(readerEnd - readerStart)
        )
    }
}

struct ReaderPresentation {
    let attributedString: NSAttributedString
    let offsetMap: ReaderOffsetMap

    static func build(
        text: String,
        sourceMap: MarkdownSourceMap,
        theme: ReaderTheme = .default,
        baseURL: URL? = nil
    ) -> ReaderPresentation {
        Builder(
            text: text,
            sourceMap: sourceMap,
            theme: theme,
            baseURL: baseURL
        ).build()
    }
}

private struct ReaderSemanticContext {
    var blockKind: MarkdownSourceMap.Kind?
    var inlineKinds: [MarkdownSourceMap.Kind]
    var linkRange: NSRange?
    var imageRange: NSRange?
}

private final class ReaderPresentationBuilder {
    let text: NSString
    let sourceMap: MarkdownSourceMap
    let theme: ReaderTheme
    let baseURL: URL?

    var output = NSMutableAttributedString()
    var records: [ReaderOffsetMap.Record] = []
    var sourceToReader: [Int]
    var readerToSource: [Int] = [0]
    var skipNewlineAt: Int?
    var sourceLineStarts: [Int] = [0]

    init(text: String, sourceMap: MarkdownSourceMap, theme: ReaderTheme, baseURL: URL?) {
        self.text = text as NSString
        self.sourceMap = sourceMap
        self.theme = theme
        self.baseURL = baseURL
        self.sourceToReader = Array(repeating: -1, count: self.text.length + 1)

        for index in 0..<self.text.length where self.text.character(at: index) == 0x0A {
            sourceLineStarts.append(index + 1)
        }
    }

    func build() -> ReaderPresentation {
        let fullRange = NSRange(location: 0, length: text.length)
        for run in sourceMap.runs(in: fullRange) {
            emit(run)
        }

        // The source map covers the complete source. This fill is defensive for
        // zero-width boundaries and makes the forward lookup total even if a
        // future parser extension introduces a gap.
        var nextReaderOffset = output.length
        for index in stride(from: sourceToReader.count - 1, through: 0, by: -1) {
            if sourceToReader[index] < 0 {
                sourceToReader[index] = nextReaderOffset
            } else {
                nextReaderOffset = sourceToReader[index]
            }
        }

        return ReaderPresentation(
            attributedString: output,
            offsetMap: ReaderOffsetMap(
                records: records,
                sourceToReader: sourceToReader,
                readerToSource: readerToSource,
                sourceLineStarts: sourceLineStarts,
                sourceLength: text.length,
                readerLength: output.length
            )
        )
    }

    private func emit(_ run: MarkdownSourceMap.Run) {
        var range = run.range

        if let skipNewlineAt,
           range.location <= skipNewlineAt,
           NSMaxRange(range) > skipNewlineAt,
           let newlineLength = newlineLength(at: skipNewlineAt),
           newlineLength > 0 {
                let omittedRange = NSRange(location: skipNewlineAt, length: newlineLength)
                markOmitted(
                    omittedRange,
                    kind: .codeBlock(fenced: true),
                    role: .syntax
                )
                range = NSRange(
                    location: skipNewlineAt + newlineLength,
                    length: NSMaxRange(range) - skipNewlineAt - newlineLength
                )
                self.skipNewlineAt = nil
        }

        guard range.length > 0 else { return }
        let adjustedRun = MarkdownSourceMap.Run(
            range: range,
            kind: run.kind,
            role: run.role
        )
        let context = context(at: range.location)

        switch adjustedRun.role {
        case .content:
            emitContent(adjustedRun, context: context)
        case .syntax:
            emitSyntax(adjustedRun, context: context)
        }
    }

    private func emitContent(
        _ run: MarkdownSourceMap.Run,
        context: ReaderSemanticContext
    ) {
        let rawText = text.substring(with: run.range)

        if isRawKind(run.kind) || context.blockKind.map(isRawKind) == true {
            append(
                rawText,
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                attributes: attributes(
                    for: run.kind,
                    context: context,
                    raw: true
                )
            )
            return
        }

        switch run.kind {
        case .softBreak:
            append(
                " ",
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                attributes: attributes(for: run.kind, context: context)
            )
        case .lineBreak:
            append(
                "\n",
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                attributes: attributes(for: run.kind, context: context)
            )
        default:
            append(
                rawText,
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                attributes: attributes(for: run.kind, context: context)
            )
        }
    }

    private func emitSyntax(
        _ run: MarkdownSourceMap.Run,
        context: ReaderSemanticContext
    ) {
        switch run.kind {
        case let .listItem(ordered, taskState):
            append(
                listMarker(for: run.range, ordered: ordered, taskState: taskState),
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                attributes: attributes(for: run.kind, context: context),
                isSubstitution: true
            )
        case .thematicBreak:
            append(
                "———",
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                attributes: attributes(for: run.kind, context: context, thematicBreak: true),
                isSubstitution: true
            )
        case .htmlBlock, .inlineHTML, .frontMatter:
            append(
                text.substring(with: run.range),
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                attributes: attributes(for: run.kind, context: context, raw: true),
                isSubstitution: true
            )
        case .codeBlock(fenced: true):
            markOmitted(run.range, kind: run.kind, role: run.role)
            if let newlineLength = newlineLength(at: NSMaxRange(run.range)), newlineLength > 0 {
                skipNewlineAt = NSMaxRange(run.range)
            }
        default:
            markOmitted(run.range, kind: run.kind, role: run.role)
        }
    }

    private func listMarker(
        for range: NSRange,
        ordered: Bool,
        taskState: MarkdownSourceMap.TaskState?
    ) -> String {
        let source = text.substring(with: range)
        var marker = source
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if ordered {
            var end = marker.startIndex
            while end < marker.endIndex,
                  marker[end].isNumber {
                end = marker.index(after: end)
            }
            if end < marker.endIndex,
               marker[end] == "." || marker[end] == ")" {
                marker = String(marker[...end]) + " "
            } else {
                marker = "1. "
            }
        } else {
            marker = "• "
        }

        if let taskState {
            let box = taskState == .checked ? "☑ " : "☐ "
            if ordered {
                marker += box
            } else {
                marker = box
            }
        }
        return marker
    }

    private func append(
        _ string: String,
        sourceRange: NSRange,
        kind: MarkdownSourceMap.Kind,
        role: MarkdownSourceMap.Role,
        attributes: [NSAttributedString.Key: Any],
        isSubstitution: Bool = false
    ) {
        let readerStart = output.length
        output.append(NSAttributedString(string: string, attributes: attributes))
        let readerLength = (string as NSString).length
        let sourceEnd = NSMaxRange(sourceRange)

        guard sourceRange.location >= 0,
              sourceEnd <= text.length else { return }

        if sourceRange.length == readerLength {
            for offset in 0..<sourceRange.length {
                sourceToReader[sourceRange.location + offset] = readerStart + offset
            }
        } else {
            for offset in 0..<sourceRange.length {
                sourceToReader[sourceRange.location + offset] = readerStart
            }
        }
        sourceToReader[sourceEnd] = readerStart + readerLength

        if readerLength > 0 {
            if sourceRange.length == readerLength {
                for offset in 1...readerLength {
                    readerToSource.append(sourceRange.location + offset)
                }
            } else {
                if readerLength > 1 {
                    for _ in 0..<(readerLength - 1) {
                        readerToSource.append(sourceRange.location)
                    }
                }
                readerToSource.append(sourceEnd)
            }
        }

        records.append(ReaderOffsetMap.Record(
            sourceRange: sourceRange,
            readerRange: NSRange(location: readerStart, length: readerLength),
            kind: kind,
            role: role,
            isSubstitution: isSubstitution
        ))
    }

    private func markOmitted(
        _ sourceRange: NSRange,
        kind: MarkdownSourceMap.Kind,
        role: MarkdownSourceMap.Role
    ) {
        let sourceEnd = NSMaxRange(sourceRange)
        guard sourceRange.location >= 0, sourceEnd <= text.length else { return }
        for offset in sourceRange.location..<sourceEnd {
            sourceToReader[offset] = output.length
        }
        sourceToReader[sourceEnd] = output.length
        records.append(ReaderOffsetMap.Record(
            sourceRange: sourceRange,
            readerRange: NSRange(location: output.length, length: 0),
            kind: kind,
            role: role,
            isSubstitution: false
        ))
    }

    private func newlineLength(at offset: Int) -> Int? {
        guard offset >= 0, offset < text.length else { return nil }
        let first = text.character(at: offset)
        if first == 0x0D {
            return offset + 1 < text.length && text.character(at: offset + 1) == 0x0A ? 2 : 1
        }
        return first == 0x0A ? 1 : nil
    }

    private func isRawKind(_ kind: MarkdownSourceMap.Kind) -> Bool {
        switch kind {
        case .table, .htmlBlock, .inlineHTML, .frontMatter:
            return true
        default:
            return false
        }
    }

    private func context(at offset: Int) -> ReaderSemanticContext {
        findContext(
            in: sourceMap.span,
            at: offset,
            current: ReaderSemanticContext(
                blockKind: nil,
                inlineKinds: [],
                linkRange: nil,
                imageRange: nil
            )
        ) ?? ReaderSemanticContext(
            blockKind: nil,
            inlineKinds: [],
            linkRange: nil,
            imageRange: nil
        )
    }

    private func findContext(
        in span: MarkdownSourceMap.Span,
        at offset: Int,
        current: ReaderSemanticContext
    ) -> ReaderSemanticContext? {
        let contains = span.range.length > 0
            && offset >= span.range.location
            && offset < NSMaxRange(span.range)
        let childContains = span.children.contains {
            $0.range.length > 0
                && offset >= $0.range.location
                && offset < NSMaxRange($0.range)
        }
        guard contains || childContains else { return nil }

        var next = current
        if isBlockKind(span.kind), next.blockKind == nil {
            next.blockKind = span.kind
        }
        switch span.kind {
        case .emphasis, .strong, .strikethrough, .codeSpan:
            if !next.inlineKinds.contains(span.kind) {
                next.inlineKinds.append(span.kind)
            }
        case .link, .autolink:
            next.inlineKinds.append(span.kind)
            next.linkRange = span.range
        case .image:
            next.inlineKinds.append(span.kind)
            next.imageRange = span.range
        default:
            break
        }

        for child in span.children.reversed() {
            if let result = findContext(in: child, at: offset, current: next) {
                return result
            }
        }
        return next
    }

    private func isBlockKind(_ kind: MarkdownSourceMap.Kind) -> Bool {
        switch kind {
        case .heading, .paragraph, .blockQuote, .listItem, .codeBlock,
             .thematicBreak, .htmlBlock, .table, .frontMatter:
            return true
        default:
            return false
        }
    }

    private func attributes(
        for runKind: MarkdownSourceMap.Kind,
        context: ReaderSemanticContext,
        raw: Bool = false,
        thematicBreak: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        let blockKind = context.blockKind
        let codeSpan = context.inlineKinds.contains(.codeSpan)
        let codeBlock: Bool
        if case .codeBlock = blockKind {
            codeBlock = true
        } else {
            codeBlock = false
        }

        let isCode = codeSpan || codeBlock || raw
        var size = theme.bodyFontSize
        var weight = NSFont.Weight.regular
        var italic = false
        var color = theme.bodyColor

        if case let .heading(level) = blockKind {
            size *= headingRatio(for: level)
            weight = .semibold
            if level == 6 {
                color = theme.secondaryColor
            }
        }
        if context.inlineKinds.contains(.strong) {
            weight = .semibold
        }
        if context.inlineKinds.contains(.emphasis) || context.inlineKinds.contains(.image) {
            italic = true
        }
        if context.inlineKinds.contains(.strikethrough) {
            color = theme.secondaryColor
        }
        if case .blockQuote = blockKind {
            color = theme.secondaryColor
        }
        if raw {
            color = theme.secondaryColor
        }
        if context.inlineKinds.contains(.image) {
            color = theme.secondaryColor
        }
        if context.inlineKinds.contains(.link) || context.inlineKinds.contains(.autolink) {
            color = theme.linkColor
        }
        if isCode {
            size *= 0.875
        }

        let font = makeFont(
            size: size,
            weight: weight,
            italic: italic,
            monospaced: isCode
        )
        let paragraphStyle = paragraphStyle(
            for: blockKind,
            thematicBreak: thematicBreak
        )

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        if isCode {
            attributes[.backgroundColor] = theme.codeBackgroundColor
        }
        if context.inlineKinds.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if context.inlineKinds.contains(.link) || context.inlineKinds.contains(.autolink),
           let destination = linkDestination(for: context.linkRange) {
            attributes[.link] = destination
        }
        return attributes
    }

    private func headingRatio(for level: Int) -> CGFloat {
        switch level {
        case 1: return 2.0
        case 2: return 1.5
        case 3: return 1.25
        case 4: return 1.0
        case 5: return 0.875
        default: return 0.85
        }
    }

    private func makeFont(
        size: CGFloat,
        weight: NSFont.Weight,
        italic: Bool,
        monospaced: Bool
    ) -> NSFont {
        let base = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return base }

        var traits = base.fontDescriptor.symbolicTraits
        traits.insert(.italic)
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private func paragraphStyle(
        for blockKind: MarkdownSourceMap.Kind?,
        thematicBreak: Bool
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.65
        style.paragraphSpacing = theme.bodyFontSize * 0.75
        style.paragraphSpacingBefore = theme.bodyFontSize * 0.75

        if thematicBreak {
            style.alignment = .center
            style.paragraphSpacing = theme.bodyFontSize
            style.paragraphSpacingBefore = theme.bodyFontSize
            return style
        }

        switch blockKind {
        case let .heading(level):
            style.lineHeightMultiple = 1.3
            style.paragraphSpacingBefore = theme.bodyFontSize * (level == 1 ? 1.5 : 1.1)
            style.paragraphSpacing = theme.bodyFontSize * 0.5
        case .listItem:
            style.paragraphSpacingBefore = theme.bodyFontSize * 0.25
            style.paragraphSpacing = theme.bodyFontSize * 0.25
            style.firstLineHeadIndent = 0
            style.headIndent = theme.bodyFontSize * 2
        case .blockQuote:
            style.paragraphSpacingBefore = theme.bodyFontSize * 0.5
            style.paragraphSpacing = theme.bodyFontSize * 0.25
            style.firstLineHeadIndent = theme.bodyFontSize
            style.headIndent = theme.bodyFontSize
        case .codeBlock:
            style.lineHeightMultiple = 1.6
            style.paragraphSpacingBefore = theme.bodyFontSize * 0.75
            style.paragraphSpacing = theme.bodyFontSize * 0.75
        default:
            break
        }
        return style
    }

    private func linkDestination(for range: NSRange?) -> Any? {
        guard let range else { return nil }
        let source = text.substring(with: range)
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") {
            return resolvedURL(String(trimmed.dropFirst().dropLast()))
        }
        if !trimmed.hasPrefix("[") && !trimmed.hasPrefix("![") {
            return resolvedURL(trimmed)
        }

        guard let closingBracket = trimmed.firstIndex(of: "]") else { return nil }
        let afterBracket = trimmed[trimmed.index(after: closingBracket)...]
        guard let openParen = afterBracket.firstIndex(of: "(") else { return nil }
        let destinationStart = afterBracket.index(after: openParen)
        let destination = afterBracket[destinationStart...]
            .split(whereSeparator: { $0 == ")" || $0.isWhitespace })
            .first
        guard let destination else { return nil }
        return resolvedURL(String(destination))
    }

    private func resolvedURL(_ string: String) -> Any {
        if let url = URL(string: string), url.scheme != nil {
            return url
        }
        if let baseURL, let url = URL(string: string, relativeTo: baseURL)?.absoluteURL {
            return url
        }
        return string
    }
}

private typealias Builder = ReaderPresentationBuilder
