import AppKit

/// Single-renderer attribute pass. Replaces both the editor's syntax
/// highlighting and the reader's ReaderPresentation builder. Computes all
/// attributes for the shared text storage based on the current mode.
final class ModeAwareHighlighter: NSObject, NSTextStorageDelegate {
    var configuration: EditorConfiguration = .default
    var mode: EditMode = .edit
    var theme: ReaderTheme = .default
    /// Source range whose syntax is revealed (cursor inside a construct).
    /// Only used in formatted mode; nil hides all syntax.
    var revealedSourceRange: NSRange?
    /// Set by the coordinator when the text view's selection changes.
    var sourceCursor: Int = 0 {
        didSet {
            guard mode == .preview, sourceCursor != oldValue else { return }
            updateReveal()
        }
    }

    private var sourceMap: MarkdownSourceMap?
    private var lastParsedRevision: UInt64 = .max
    private var isHighlighting = false
    private(set) var needsFullHighlight = true
    private var pendingCompositionRange: NSRange?
    var isEnabled = true

    var needsDeferredHighlight: Bool {
        needsFullHighlight || pendingCompositionRange != nil
    }

    func updateConfiguration(_ configuration: EditorConfiguration) -> Bool {
        guard !configuration.isHighlightingEquivalent(to: self.configuration) else { return false }
        self.configuration = configuration
        if !isEnabled {
            needsFullHighlight = true
        }
        return true
    }

    func updateMode(_ mode: EditMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        needsFullHighlight = true
    }

    func updateReveal() {
        guard mode == .preview else { return }
        guard let sourceMap else { return }
        revealedSourceRange = ReaderReveal.range(in: sourceMap, sourceCursor: sourceCursor)
    }

    // MARK: - NSTextStorageDelegate

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
        guard !isHighlighting else { return }

        if hasActiveComposition {
            rememberCompositionRange(in: textStorage, editedRange: editedRange)
            return
        }

        let combinedRange = pendingCompositionRange.map { NSUnionRange($0, editedRange) } ?? editedRange
        pendingCompositionRange = nil
        let range = lineRange(in: textStorage.string, for: combinedRange)
        highlight(textStorage, in: range)
    }

    private var hasActiveComposition: Bool {
        textView?.isComposingText ?? false
    }

    private(set) weak var textView: MarkdownNSTextView?

    func attach(textView: MarkdownNSTextView) {
        self.textView = textView
    }

    private func rememberCompositionRange(in storage: NSTextStorage, editedRange: NSRange) {
        let fullRange = lineRange(in: storage.string, for: editedRange)
        pendingCompositionRange = pendingCompositionRange.map { NSUnionRange($0, fullRange) } ?? fullRange
    }

    func flushDeferredHighlight(in storage: NSTextStorage) {
        guard isEnabled, !hasActiveComposition else { return }
        if needsFullHighlight {
            highlightAll(in: storage)
            return
        }
        guard let pendingCompositionRange else { return }
        self.pendingCompositionRange = nil
        let safeLocation = min(pendingCompositionRange.location, storage.length)
        let safeEnd = min(NSMaxRange(pendingCompositionRange), storage.length)
        let safeRange = NSRange(location: safeLocation, length: max(0, safeEnd - safeLocation))
        highlight(storage, in: lineRange(in: storage.string, for: safeRange))
    }

    func highlightAll(in storage: NSTextStorage) {
        guard isEnabled else { return }
        guard !hasActiveComposition else {
            needsFullHighlight = true
            return
        }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            needsFullHighlight = false
            return
        }
        highlight(storage, in: fullRange)
        needsFullHighlight = false
        pendingCompositionRange = nil
    }

    // MARK: - Attribute computation

    private func highlight(_ storage: NSTextStorage, in range: NSRange) {
        guard isEnabled, range.length > 0, NSMaxRange(range) <= storage.length else { return }
        isHighlighting = true
        storage.beginEditing()
        defer {
            storage.endEditing()
            isHighlighting = false
        }

        let text = storage.string
        let revision = textView?.document?.textRevision ?? 0
        if sourceMap == nil || revision != lastParsedRevision {
            sourceMap = MarkdownSourceMap.parse(text)
            lastParsedRevision = revision
            updateReveal()
        }

        guard let sourceMap else { return }

        let clearRange = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.font, range: clearRange)
        storage.removeAttribute(.foregroundColor, range: clearRange)
        storage.removeAttribute(.paragraphStyle, range: clearRange)
        storage.removeAttribute(.kern, range: clearRange)
        storage.removeAttribute(.ligature, range: clearRange)
        storage.removeAttribute(.readerCodeSpan, range: clearRange)
        storage.removeAttribute(.readerCodeBlock, range: clearRange)
        storage.removeAttribute(.readerBlockQuote, range: clearRange)
        storage.removeAttribute(.readerHeadingLevel, range: clearRange)
        storage.removeAttribute(.readerThematicBreak, range: clearRange)
        storage.removeAttribute(.readerFrontMatter, range: clearRange)

        let baseFont = configuration.font
        let baseColor = configuration.textColor
        let baseStyle = NSMutableParagraphStyle()
        baseStyle.lineHeightMultiple = configuration.lineHeightMultiple

        storage.addAttribute(.font, value: baseFont, range: clearRange)
        storage.addAttribute(.foregroundColor, value: baseColor, range: clearRange)
        storage.addAttribute(.paragraphStyle, value: baseStyle, range: clearRange)
        storage.addAttribute(.ligature, value: 0, range: clearRange)

        if ArealFont.isAvailable {
            storage.addAttribute(.kern, value: ArealFont.monoTracking, range: clearRange)
        }

        for run in sourceMap.runs(in: clearRange) {
            let runRange = run.range
            guard runRange.length > 0, NSMaxRange(runRange) <= storage.length else { continue }

            switch mode {
            case .edit:
                applyEditModeAttributes(storage: storage, run: run, range: runRange)
            case .preview:
                applyPreviewModeAttributes(storage: storage, run: run, range: runRange, sourceMap: sourceMap)
            }
        }

        storage.fixFontAttribute(in: clearRange)
        updateHiddenRanges(storage: storage, sourceMap: sourceMap)
    }

    // MARK: - Edit mode attributes

    private func applyEditModeAttributes(storage: NSTextStorage, run: MarkdownSourceMap.Run, range: NSRange) {
        for rule in Self.rules {
            for match in rule.regex.matches(in: storage.string, range: range) {
                guard NSMaxRange(match.range) <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: color(for: rule.color), range: match.range)
            }
        }

        if case .heading = run.kind {
            let boldFont = ArealFont.font(size: configuration.fontSize, weight: .bold, mono: 100)
                ?? NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .bold)
            storage.addAttribute(.font, value: boldFont, range: range)
        }
    }

    // MARK: - Preview mode attributes

    private func applyPreviewModeAttributes(
        storage: NSTextStorage,
        run: MarkdownSourceMap.Run,
        range: NSRange,
        sourceMap: MarkdownSourceMap
    ) {
        let context = context(at: range.location, in: sourceMap)
        let blockKind = context.blockKind
        let codeSpan = context.hasCodeSpan
        let codeBlock: Bool
        if case .codeBlock = blockKind {
            codeBlock = true
        } else {
            codeBlock = false
        }
        let isCode = codeSpan || codeBlock

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
        if context.hasStrong {
            weight = .semibold
        }
        if context.hasEmphasis || context.hasImage {
            italic = true
        }
        if context.hasStrikethrough {
            color = theme.secondaryColor
        }
        if case .blockQuote = blockKind {
            color = theme.secondaryColor
        }
        if context.hasImage {
            color = theme.secondaryColor
        }
        if context.hasLink || context.hasAutolink {
            color = theme.linkColor
        }
        if isCode {
            size *= 0.875
        }

        let font = makeFont(size: size, weight: weight, italic: italic, monospaced: isCode)
        storage.addAttribute(.font, value: font, range: range)
        storage.addAttribute(.foregroundColor, value: color, range: range)

        let paragraphStyle = paragraphStyle(for: blockKind, listDepth: context.listDepth)
        storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        if codeSpan {
            storage.addAttribute(.readerCodeSpan, value: true, range: range)
        }
        if codeBlock {
            storage.addAttribute(.readerCodeBlock, value: NSValue(
                range: context.blockRange ?? NSRange(location: 0, length: 0)
            ), range: range)
        }
        if case let .heading(level) = blockKind {
            storage.addAttribute(.readerHeadingLevel, value: level, range: range)
        }
        if case .blockQuote = blockKind {
            storage.addAttribute(.readerBlockQuote, value: true, range: range)
        }
        if case .thematicBreak = run.kind {
            storage.addAttribute(.readerThematicBreak, value: true, range: range)
        }
        if case .frontMatter = run.kind {
            storage.addAttribute(.readerFrontMatter, value: true, range: range)
        }

        if isCode, ArealFont.isAvailable {
            storage.addAttribute(.kern, value: ArealFont.monoTracking, range: range)
        }
    }

    // MARK: - Hidden ranges (formatted mode)

    private func updateHiddenRanges(storage: NSTextStorage, sourceMap: MarkdownSourceMap) {
        guard mode == .preview else {
            textView?.markdownLayoutManager?.hiddenCharacterRanges = []
            return
        }

        var hidden: [NSRange] = []
        collectSyntaxRanges(in: sourceMap.span, storage: storage, into: &hidden)

        if let revealed = revealedSourceRange {
            hidden = hidden.filter { NSIntersectionRange($0, revealed).length == 0 }
        }

        textView?.markdownLayoutManager?.hiddenCharacterRanges = hidden
    }

    private func collectSyntaxRanges(
        in span: MarkdownSourceMap.Span,
        storage: NSTextStorage,
        into result: inout [NSRange]
    ) {
        if span.role == .content {
            // Front matter collapses to its closing rule; the whole block is
            // hidden, including trailing newlines so no empty lines remain.
            if case .frontMatter = span.kind {
                result.append(extendedThroughNewline(span.range, storage: storage))
            }
            for child in span.children where child.role == .syntax {
                switch child.kind {
                case .listItem, .thematicBreak, .frontMatter:
                    continue
                case .codeBlock:
                    // Fence lines disappear with their newline so the code
                    // block's background sits flush with surrounding text.
                    result.append(extendedThroughNewline(child.range, storage: storage))
                default:
                    result.append(child.range)
                }
            }
        }
        for child in span.children {
            collectSyntaxRanges(in: child, storage: storage, into: &result)
        }
    }

    /// Extends a hidden range through the newline that ends its line. The
    /// layout manager collapses a fully hidden line's fragment to zero height,
    /// so hiding the newline is what removes the empty line.
    private func extendedThroughNewline(_ range: NSRange, storage: NSTextStorage) -> NSRange {
        let text = storage.string as NSString
        var end = NSMaxRange(range)
        if end < text.length, text.character(at: end) == 0x0D { end += 1 }
        if end < text.length, text.character(at: end) == 0x0A { end += 1 }
        return NSRange(location: range.location, length: end - range.location)
    }

    // MARK: - Font building

    private func makeFont(
        size: CGFloat,
        weight: NSFont.Weight,
        italic: Bool,
        monospaced: Bool
    ) -> NSFont {
        if ArealFont.isAvailable,
           let areal = ArealFont.font(
               size: size,
               weight: weight,
               italic: italic,
               mono: monospaced ? 100 : 0
           ) {
            return areal
        }
        let base = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return base }
        var traits = base.fontDescriptor.symbolicTraits
        traits.insert(.italic)
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    // MARK: - Paragraph styles

    private func paragraphStyle(for blockKind: MarkdownSourceMap.Kind?, listDepth: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = configuration.lineHeightMultiple

        if case .blockQuote = blockKind {
            style.firstLineHeadIndent = 16
            style.headIndent = 16
        }
        if case .listItem = blockKind {
            let indent = 24 + CGFloat(listDepth) * 24
            style.firstLineHeadIndent = indent
            style.headIndent = indent
        }
        if case .codeBlock = blockKind {
            style.firstLineHeadIndent = 12
            style.headIndent = 12
        }

        return style
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

    // MARK: - Context

    private struct SemanticContext {
        let blockKind: MarkdownSourceMap.Kind?
        let blockRange: NSRange?
        let hasEmphasis: Bool
        let hasStrong: Bool
        let hasStrikethrough: Bool
        let hasCodeSpan: Bool
        let hasLink: Bool
        let hasImage: Bool
        let hasAutolink: Bool
        let listDepth: Int
    }

    private func context(at offset: Int, in sourceMap: MarkdownSourceMap) -> SemanticContext {
        var blockKind: MarkdownSourceMap.Kind?
        var blockRange: NSRange?
        var hasEmphasis = false
        var hasStrong = false
        var hasStrikethrough = false
        var hasCodeSpan = false
        var hasLink = false
        var hasImage = false
        var hasAutolink = false
        var listDepth = 0

        func walk(_ span: MarkdownSourceMap.Span) {
            guard span.range.location <= offset, offset < NSMaxRange(span.range) else { return }
            if span.role == .content {
                switch span.kind {
                case .heading, .paragraph, .blockQuote, .listItem, .codeBlock, .thematicBreak,
                     .htmlBlock, .table, .frontMatter:
                    blockKind = span.kind
                    blockRange = span.range
                case .emphasis: hasEmphasis = true
                case .strong: hasStrong = true
                case .strikethrough: hasStrikethrough = true
                case .codeSpan: hasCodeSpan = true
                case .link: hasLink = true
                case .image: hasImage = true
                case .autolink: hasAutolink = true
                default:
                    break
                }
                if case .listItem = span.kind {
                    listDepth += 1
                }
            }
            for child in span.children {
                walk(child)
            }
        }

        walk(sourceMap.span)
        return SemanticContext(
            blockKind: blockKind,
            blockRange: blockRange,
            hasEmphasis: hasEmphasis,
            hasStrong: hasStrong,
            hasStrikethrough: hasStrikethrough,
            hasCodeSpan: hasCodeSpan,
            hasLink: hasLink,
            hasImage: hasImage,
            hasAutolink: hasAutolink,
            listDepth: max(0, listDepth - 1)
        )
    }

    // MARK: - Syntax highlighting rules

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
        Rule(regex: try! NSRegularExpression(pattern: #"^[\-\*] \[ [xX]\]"#, options: [.anchorsMatchLines]), color: .yellow),
        Rule(regex: try! NSRegularExpression(pattern: #"^(\*{3,}|-{3,}|_{3,})\s*$"#, options: [.anchorsMatchLines]), color: .gray),
    ]

    private static let headingRule: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^#{1,6}\\s.*$", options: [.anchorsMatchLines])
    }()

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

    private func lineRange(in text: String, for range: NSRange) -> NSRange {
        let nsText = text as NSString
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        nsText.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: range)
        return NSRange(location: lineStart, length: lineEnd - lineStart)
    }
}
