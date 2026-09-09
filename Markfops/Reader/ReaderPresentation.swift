import AppKit
import Foundation

extension NSAttributedString.Key {
    static let readerCodeSpan = NSAttributedString.Key("com.markfops.reader.codeSpan")
    static let readerCodeBlock = NSAttributedString.Key("com.markfops.reader.codeBlock")
    static let readerBlockQuote = NSAttributedString.Key("com.markfops.reader.blockQuote")
    static let readerHeadingLevel = NSAttributedString.Key("com.markfops.reader.headingLevel")
    static let readerThematicBreak = NSAttributedString.Key("com.markfops.reader.thematicBreak")
    static let readerFrontMatter = NSAttributedString.Key("com.markfops.reader.frontMatter")
}

struct ReaderTheme {
    var bodyFontSize: CGFloat
    var bodyColor: NSColor
    var backgroundColor: NSColor
    var secondaryColor: NSColor
    var linkColor: NSColor
    var codeBackgroundColor: NSColor
    var separatorColor: NSColor
    var contentInsets: NSEdgeInsets
    var maxContentWidth: CGFloat

    static var `default`: ReaderTheme {
        ReaderTheme(
            bodyFontSize: 16,
            bodyColor: .textColor,
            backgroundColor: .textBackgroundColor,
            secondaryColor: .secondaryLabelColor,
            linkColor: .linkColor,
            codeBackgroundColor: NSColor.textColor.withAlphaComponent(0.06),
            separatorColor: .separatorColor,
            contentInsets: NSEdgeInsets(top: 40, left: 32, bottom: 80, right: 32),
            maxContentWidth: 780
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
    var blockRange: NSRange?
    var inlineKinds: [MarkdownSourceMap.Kind]
    var linkRange: NSRange?
    var imageRange: NSRange?
    var listDepth: Int

    static var empty: ReaderSemanticContext {
        ReaderSemanticContext(
            blockKind: nil,
            blockRange: nil,
            inlineKinds: [],
            linkRange: nil,
            imageRange: nil,
            listDepth: 0
        )
    }
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
    var handledImageRanges: [NSRange] = []
    var handledRawBlockRanges: [NSRange] = []

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
        if handledImageRanges.contains(where: {
            $0.location <= run.range.location
                && NSMaxRange(run.range) <= NSMaxRange($0)
        }) {
            return
        }
        if handledRawBlockRanges.contains(where: {
            $0.location <= run.range.location
                && NSMaxRange(run.range) <= NSMaxRange($0)
        }) {
            return
        }

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

        if case .codeBlock = context.blockKind {
            appendBlockText(
                rawText,
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                context: context
            )
            return
        }

        if case .table = context.blockKind {
            emitRawBlockIfNeeded(context: context)
            return
        }
        if case .htmlBlock = context.blockKind {
            emitRawBlockIfNeeded(context: context)
            return
        }

        if isRawKind(run.kind) || context.blockKind.map(isRawKind) == true {
            appendBlockText(
                rawText,
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                context: context,
                raw: true
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
            let isCodeSpan = context.inlineKinds.contains(.codeSpan)
            if isCodeSpan {
                padBeforeCodeSpan()
            }
            appendContentText(
                rawText,
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                context: context
            )
            if isCodeSpan {
                padAfterCodeSpan()
            }
        }
    }

    /// Inline code capsules need room on both sides. Kerning the neighbouring
    /// characters adds that room without adding characters, so the offset map
    /// stays intact.
    private var codeSpanPadding: CGFloat { theme.bodyFontSize * 0.3 }

    private func padBeforeCodeSpan() {
        guard output.length > 0 else { return }
        let previous = NSRange(location: output.length - 1, length: 1)
        let previousCharacter = (output.string as NSString).character(at: previous.location)
        guard previousCharacter != 0x0A,
              output.attribute(.readerCodeSpan, at: previous.location, effectiveRange: nil) == nil else { return }
        output.addAttribute(.kern, value: codeSpanPadding, range: previous)
    }

    private func padAfterCodeSpan() {
        guard output.length > 0 else { return }
        let last = NSRange(location: output.length - 1, length: 1)
        let lastCharacter = (output.string as NSString).character(at: last.location)
        guard lastCharacter != 0x0A else { return }
        output.addAttribute(.kern, value: codeSpanPadding, range: last)
    }

    private func appendContentText(
        _ string: String,
        sourceRange: NSRange,
        kind: MarkdownSourceMap.Kind,
        role: MarkdownSourceMap.Role,
        context: ReaderSemanticContext
    ) {
        let source = string as NSString
        var localStart = 0

        while localStart < source.length {
            let remaining = NSRange(location: localStart, length: source.length - localStart)
            let newline = source.range(of: "\n", options: [], range: remaining)
            let localEnd = newline.location == NSNotFound
                ? source.length
                : NSMaxRange(newline)
            let localRange = NSRange(location: localStart, length: localEnd - localStart)
            let absoluteRange = NSRange(
                location: sourceRange.location + localRange.location,
                length: localRange.length
            )
            let lineContext = self.context(at: absoluteRange.location)
            let line = source.substring(with: localRange)
            let isBlankLine = line == "\n"
                && lineContext.blockKind == nil
                && (absoluteRange.location == 0
                    || text.character(at: absoluteRange.location - 1) == 0x0A)
            append(
                line,
                sourceRange: absoluteRange,
                kind: kind,
                role: role,
                attributes: attributes(
                    for: kind,
                    context: lineContext,
                    blankLine: isBlankLine
                )
            )
            localStart = localEnd
        }
    }

    private func emitRawBlockIfNeeded(context: ReaderSemanticContext) {
        guard let blockRange = context.blockRange,
              !handledRawBlockRanges.contains(blockRange) else { return }
        appendBlockText(
            text.substring(with: blockRange),
            sourceRange: blockRange,
            kind: context.blockKind ?? .text,
            role: .content,
            context: context,
            raw: true
        )
        handledRawBlockRanges.append(blockRange)
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
                "\u{200B}",
                sourceRange: run.range,
                kind: run.kind,
                role: run.role,
                attributes: attributes(for: run.kind, context: context, thematicBreak: true),
                isSubstitution: true
            )
        case .frontMatter:
            emitFrontMatter(run.range)
        case .image:
            if let imageRange = context.imageRange,
               let image = localImage(for: imageRange) {
                emitImage(image, sourceRange: imageRange)
                handledImageRanges.append(imageRange)
            } else {
                markOmitted(run.range, kind: run.kind, role: run.role)
            }
        case .htmlBlock:
            if case .htmlBlock = context.blockKind {
                emitRawBlockIfNeeded(context: context)
            } else {
                appendBlockText(
                    text.substring(with: run.range),
                    sourceRange: run.range,
                    kind: run.kind,
                    role: run.role,
                    context: context,
                    raw: true
                )
            }
        case .inlineHTML:
            if case .htmlBlock = context.blockKind {
                emitRawBlockIfNeeded(context: context)
            } else {
                append(
                    text.substring(with: run.range),
                    sourceRange: run.range,
                    kind: run.kind,
                    role: run.role,
                    attributes: attributes(for: run.kind, context: context, raw: true),
                    isSubstitution: true
                )
            }
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
        append(
            NSAttributedString(string: string, attributes: attributes),
            sourceRange: sourceRange,
            kind: kind,
            role: role,
            isSubstitution: isSubstitution
        )
    }

    private func append(
        _ attributedString: NSAttributedString,
        sourceRange: NSRange,
        kind: MarkdownSourceMap.Kind,
        role: MarkdownSourceMap.Role,
        isSubstitution: Bool = false
    ) {
        let readerStart = output.length
        output.append(attributedString)
        let readerLength = attributedString.length
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

    private func appendBlockText(
        _ string: String,
        sourceRange: NSRange,
        kind: MarkdownSourceMap.Kind,
        role: MarkdownSourceMap.Role,
        context: ReaderSemanticContext,
        raw: Bool = false
    ) {
        let source = string as NSString
        var localStart = 0
        var lineNumber = 0

        while localStart < source.length {
            let remaining = NSRange(location: localStart, length: source.length - localStart)
            let newline = source.range(of: "\n", options: [], range: remaining)
            let localEnd: Int
            if newline.location != NSNotFound {
                localEnd = NSMaxRange(newline)
            } else {
                localEnd = source.length
            }

            let localRange = NSRange(location: localStart, length: localEnd - localStart)
            let lineRange = NSRange(
                location: sourceRange.location + localRange.location,
                length: localRange.length
            )
            let atFirstLine = lineNumber == 0
            let atLastLine = localEnd == source.length
            append(
                source.substring(with: localRange),
                sourceRange: lineRange,
                kind: kind,
                role: role,
                attributes: attributes(
                    for: kind,
                    context: context,
                    raw: raw,
                    blockLine: (atFirstLine, atLastLine)
                )
            )
            localStart = localEnd
            lineNumber += 1
        }
    }

    private func emitFrontMatter(_ sourceRange: NSRange) {
        guard let frontMatter = MarkdownFrontMatter.extract(
            from: text.substring(with: sourceRange)
        ) else {
            append(
                text.substring(with: sourceRange),
                sourceRange: sourceRange,
                kind: .frontMatter,
                role: .syntax,
                attributes: attributes(
                    for: .frontMatter,
                    context: ReaderSemanticContext.empty,
                    raw: true
                ),
                isSubstitution: true
            )
            return
        }

        let rows = MarkdownFrontMatter.rows(from: frontMatter.value)
        let keyFont = makeFont(
            size: theme.bodyFontSize * 0.875,
            weight: .regular,
            italic: false,
            monospaced: true
        )
        let valueFont = makeFont(
            size: theme.bodyFontSize,
            weight: .regular,
            italic: false,
            monospaced: false
        )
        let keyWidth = rows.map { row in
            (row.key as NSString).size(withAttributes: [.font: keyFont]).width
        }.max() ?? 0
        let tabLocation = min(
            max(theme.bodyFontSize * 7, keyWidth + theme.bodyFontSize),
            theme.maxContentWidth * 0.5
        )
        let paragraphStyle = frontMatterParagraphStyle(tabLocation: tabLocation)
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: keyFont,
            .foregroundColor: theme.secondaryColor,
            .paragraphStyle: paragraphStyle,
            .ligature: 0,
            .readerFrontMatter: true,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: theme.bodyColor,
            .paragraphStyle: paragraphStyle,
            .ligature: 0,
            .readerFrontMatter: true,
        ]

        let rendered = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            if index > 0 {
                rendered.append(NSAttributedString(string: "\n", attributes: valueAttributes))
            }
            if !row.key.isEmpty {
                rendered.append(NSAttributedString(string: row.key, attributes: keyAttributes))
                rendered.append(NSAttributedString(string: "\t", attributes: valueAttributes))
            }
            let firstValue = row.valueLines.first ?? ""
            rendered.append(NSAttributedString(string: firstValue, attributes: valueAttributes))
            for continuation in row.valueLines.dropFirst() {
                rendered.append(NSAttributedString(string: "\n\t", attributes: valueAttributes))
                rendered.append(NSAttributedString(string: continuation, attributes: valueAttributes))
            }
        }
        if rendered.length > 0 {
            rendered.append(NSAttributedString(string: "\n", attributes: valueAttributes))
        }

        append(
            rendered,
            sourceRange: sourceRange,
            kind: .frontMatter,
            role: .syntax,
            isSubstitution: true
        )
    }

    private func emitImage(_ image: NSImage, sourceRange: NSRange) {
        let imageAttachment = ReaderImageAttachment(image: roundedImage(image, radius: 6))
        let imageParagraph = NSMutableParagraphStyle()
        imageParagraph.alignment = .center
        imageParagraph.lineHeightMultiple = 1
        imageParagraph.paragraphSpacingBefore = theme.bodyFontSize * 0.75
        imageParagraph.paragraphSpacing = theme.bodyFontSize * 0.25

        let rendered = NSMutableAttributedString()
        let attachmentString = NSAttributedString(attachment: imageAttachment)
        rendered.append(attachmentString)
        rendered.addAttributes([
            .font: makeFont(
                size: theme.bodyFontSize,
                weight: .regular,
                italic: false,
                monospaced: false
            ),
            .paragraphStyle: imageParagraph,
            .ligature: 0,
        ], range: NSRange(location: 0, length: rendered.length))

        let source = text.substring(with: sourceRange)
        let altText = imageAltText(in: source)
        if !altText.isEmpty {
            let altParagraph = imageParagraph.mutableCopy() as! NSMutableParagraphStyle
            altParagraph.paragraphSpacingBefore = 0
            altParagraph.paragraphSpacing = theme.bodyFontSize * 0.75
            rendered.append(NSAttributedString(string: "\n\(altText)", attributes: [
                .font: makeFont(
                    size: theme.bodyFontSize * 0.875,
                    weight: .regular,
                    italic: true,
                    monospaced: false
                ),
                .foregroundColor: theme.secondaryColor,
                .paragraphStyle: altParagraph,
                .ligature: 0,
            ]))
        }
        rendered.append(NSAttributedString(string: "\n", attributes: [
            .font: makeFont(
                size: theme.bodyFontSize,
                weight: .regular,
                italic: false,
                monospaced: false
            ),
            .paragraphStyle: imageParagraph,
            .ligature: 0,
        ]))

        append(
            rendered,
            sourceRange: sourceRange,
            kind: .image,
            role: .content,
            isSubstitution: true
        )
    }

    private func imageAltText(in source: String) -> String {
        guard let opening = source.firstIndex(of: "["),
              let closing = source[opening...].firstIndex(of: "]"),
              opening < closing else { return "" }
        return String(source[source.index(after: opening)..<closing])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func localImage(for sourceRange: NSRange) -> NSImage? {
        guard let destination = linkDestination(for: sourceRange) as? URL,
              destination.isFileURL,
              FileManager.default.fileExists(atPath: destination.path) else {
            return nil
        }
        return NSImage(contentsOf: destination)
    }

    private func roundedImage(_ image: NSImage, radius: CGFloat) -> NSImage {
        let rounded = NSImage(size: image.size)
        rounded.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let path = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: image.size),
            xRadius: radius,
            yRadius: radius
        )
        path.addClip()
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        rounded.unlockFocus()
        return rounded
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
            current: .empty
        ) ?? .empty
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
        // Syntax spans carry their parent's kind (a list marker is a listItem span,
        // an image's "!" is an image span). Only content spans define the context.
        if span.role == .content {
            if isBlockKind(span.kind), next.blockKind == nil {
                next.blockKind = span.kind
                next.blockRange = span.range
            }
            switch span.kind {
            case .listItem:
                next.listDepth += 1
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
        thematicBreak: Bool = false,
        blockLine: (isFirst: Bool, isLast: Bool)? = nil,
        blankLine: Bool = false
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
        let paragraphStyle = blankLine
            ? blankLineParagraphStyle()
            : paragraphStyle(
                for: blockKind,
                thematicBreak: thematicBreak,
                blockLine: blockLine,
                listDepth: context.listDepth
            )

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
            // TextKit must expose one glyph position per UTF-16 character while
            // the morph is pairing source and reader offsets.
            .ligature: 0,
        ]

        if codeSpan {
            attributes[.readerCodeSpan] = true
        }
        if codeBlock || raw {
            attributes[.readerCodeBlock] = NSValue(
                range: context.blockRange ?? NSRange(location: 0, length: 0)
            )
        }
        if case let .heading(level) = blockKind {
            attributes[.readerHeadingLevel] = level
        }
        if case .blockQuote = blockKind {
            attributes[.readerBlockQuote] = true
        }
        if thematicBreak {
            attributes[.readerThematicBreak] = true
        }
        if context.inlineKinds.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if context.inlineKinds.contains(.link) || context.inlineKinds.contains(.autolink),
           let destination = linkDestination(for: context.linkRange) {
            attributes[.link] = destination
        }
        if case .frontMatter = runKind {
            attributes[.readerFrontMatter] = true
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
        thematicBreak: Bool,
        blockLine: (isFirst: Bool, isLast: Bool)? = nil,
        listDepth: Int = 0
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
            let depth = max(0, listDepth - 1)
            let markerIndent = theme.bodyFontSize * 2 * CGFloat(depth)
            style.paragraphSpacingBefore = theme.bodyFontSize * 0.25
            style.paragraphSpacing = theme.bodyFontSize * 0.25
            style.firstLineHeadIndent = markerIndent
            style.headIndent = markerIndent + theme.bodyFontSize * 2
            style.tabStops = [NSTextTab(
                textAlignment: .left,
                location: markerIndent + theme.bodyFontSize * 2
            )]
        case .blockQuote:
            style.paragraphSpacingBefore = theme.bodyFontSize * 0.25
            style.paragraphSpacing = theme.bodyFontSize * 0.25
            style.firstLineHeadIndent = theme.bodyFontSize
            style.headIndent = theme.bodyFontSize
        case .codeBlock:
            style.lineHeightMultiple = 1.6
            style.paragraphSpacingBefore = blockLine?.isFirst == true
                ? theme.bodyFontSize * 1.25
                : 0
            style.paragraphSpacing = blockLine?.isLast == true
                ? theme.bodyFontSize * 1.25
                : 0
            style.firstLineHeadIndent = theme.bodyFontSize * 1.25
            style.headIndent = theme.bodyFontSize * 1.25
            style.tailIndent = -theme.bodyFontSize * 1.25
        case .table, .htmlBlock:
            style.lineHeightMultiple = 1.6
            style.paragraphSpacingBefore = blockLine?.isFirst == true
                ? theme.bodyFontSize * 1.25
                : 0
            style.paragraphSpacing = blockLine?.isLast == true
                ? theme.bodyFontSize * 1.25
                : 0
            style.firstLineHeadIndent = theme.bodyFontSize * 1.25
            style.headIndent = theme.bodyFontSize * 1.25
            style.tailIndent = -theme.bodyFontSize * 1.25
        default:
            break
        }
        return style
    }

    /// An empty source line stays in the reader text so source and reader lines
    /// keep pairing, but it must not read as a full body line. The neighbours'
    /// own paragraph spacing is the visible gap; the line itself collapses.
    private func blankLineParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1
        style.minimumLineHeight = theme.bodyFontSize * 0.25
        style.maximumLineHeight = theme.bodyFontSize * 0.25
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = 0
        return style
    }

    private func frontMatterParagraphStyle(tabLocation: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = theme.bodyFontSize * 0.2
        style.tabStops = [NSTextTab(textAlignment: .left, location: tabLocation)]
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
        if let baseURL {
            if baseURL.isFileURL {
                let directoryURL = baseURL.hasDirectoryPath
                    ? baseURL
                    : URL(fileURLWithPath: baseURL.path, isDirectory: true)
                return directoryURL.appendingPathComponent(string)
            }
            if let url = URL(string: string, relativeTo: baseURL)?.absoluteURL {
                return url
            }
        }
        return string
    }
}

private final class ReaderImageAttachment: NSTextAttachment {
    init(image: NSImage) {
        super.init(data: nil, ofType: nil)
        self.image = image
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        guard let image,
              image.size.width > 0,
              image.size.height > 0 else {
            return super.attachmentBounds(
                for: textContainer,
                proposedLineFragment: lineFrag,
                glyphPosition: glyphPosition,
                characterIndex: charIndex
            )
        }

        let availableWidth = max(1, lineFrag.width)
        let scale = min(1, availableWidth / image.size.width)
        return NSRect(
            x: 0,
            y: 0,
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }
}

private typealias Builder = ReaderPresentationBuilder
