import AppKit

extension NSAttributedString.Key {
    static let readerCodeSpan = NSAttributedString.Key("com.markfops.reader.codeSpan")
    static let readerCodeBlock = NSAttributedString.Key("com.markfops.reader.codeBlock")
    static let readerBlockQuote = NSAttributedString.Key("com.markfops.reader.blockQuote")
    static let readerHeadingLevel = NSAttributedString.Key("com.markfops.reader.headingLevel")
    static let readerThematicBreak = NSAttributedString.Key("com.markfops.reader.thematicBreak")
    static let readerFrontMatter = NSAttributedString.Key("com.markfops.reader.frontMatter")
}

/// Colors and metrics for preview-mode decorations. Was the reader theme;
/// now the layout manager and highlighter share it.
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

/// Layout manager for the single-renderer architecture. Merges the reader's
/// decorations (code blocks, capsules, quote bars, heading rules, front matter,
/// thematic breaks) with hidden-syntax support for formatted mode.
final class MarkdownLayoutManager: NSLayoutManager {
    var theme: ReaderTheme = .default
    /// Whether formatted-mode decorations are drawn. Edit mode skips them.
    var showsDecorations = true
    /// Whole-view glyph opacity, kept for the transition period. Will be
    /// removed once the mode morph is gone.
    var morphGlyphOpacity: CGFloat = 1
    /// Character ranges whose glyphs are not drawn while a reveal transition
    /// animates copies of them. In formatted mode this also holds the ranges
    /// of hidden Markdown syntax (e.g. ** around bold text).
    var hiddenCharacterRanges: [NSRange] = [] {
        didSet {
            for range in oldValue + hiddenCharacterRanges where range.length > 0 {
                invalidateDisplay(forCharacterRange: range)
                invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            }
        }
    }

    /// A hidden character range that ends in a newline is a fully hidden line
    /// (front matter, fenced-code fence lines in preview). Nothing is drawn in
    /// its place, so the empty line fragment must collapse to zero height;
    /// NSLayoutManager still gives invisible newlines a full-height line
    /// fragment otherwise.
    override func setLineFragmentRect(
        _ fragmentRect: NSRect,
        forGlyphRange glyphRange: NSRange,
        usedRect: NSRect
    ) {
        var fragmentRect = fragmentRect
        var usedRect = usedRect
        if glyphRange.length == 1, glyphAtIndexIsFullyHiddenLineBreak(glyphRange.location) {
            fragmentRect.size.height = 0
            usedRect.size.height = 0
        }
        super.setLineFragmentRect(fragmentRect, forGlyphRange: glyphRange, usedRect: usedRect)
    }

    private func glyphAtIndexIsFullyHiddenLineBreak(_ glyphIndex: Int) -> Bool {
        let characterIndex = characterIndexForGlyph(at: glyphIndex)
        guard let storage = textStorage,
              characterIndex < storage.length,
              (storage.string as NSString).character(at: characterIndex) == 0x0A else { return false }
        return hiddenCharacterRanges.contains { range in
            range.location <= characterIndex && characterIndex < NSMaxRange(range)
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard morphGlyphOpacity > 0 else { return }
        if morphGlyphOpacity >= 1 {
            drawUnhiddenGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            drawUnhiddenGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        context.saveGState()
        context.setAlpha(morphGlyphOpacity)
        drawUnhiddenGlyphs(forGlyphRange: glyphsToShow, at: origin)
        context.restoreGState()
    }

    /// Draws the requested glyphs in pieces, leaving out the hidden ranges.
    private func drawUnhiddenGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !hiddenCharacterRanges.isEmpty else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let hiddenGlyphRanges = hiddenCharacterRanges
            .map { glyphRange(forCharacterRange: $0, actualCharacterRange: nil) }
            .map { NSIntersectionRange($0, glyphsToShow) }
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
        var cursor = glyphsToShow.location
        for hidden in hiddenGlyphRanges {
            if hidden.location > cursor {
                super.drawGlyphs(
                    forGlyphRange: NSRange(location: cursor, length: hidden.location - cursor),
                    at: origin
                )
            }
            cursor = max(cursor, NSMaxRange(hidden))
        }
        let end = NSMaxRange(glyphsToShow)
        if cursor < end {
            super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: end - cursor), at: origin)
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard showsDecorations,
              glyphsToShow.length > 0,
              let storage = textStorage,
              let textContainer = textContainers.first else { return }

        let characterRange = characterRange(
            forGlyphRange: glyphsToShow,
            actualGlyphRange: nil
        )
        ensureLayout(forGlyphRange: glyphsToShow)

        drawCodeBlocks(
            in: characterRange,
            storage: storage,
            textContainer: textContainer,
            origin: origin
        )
        drawInlineCodeCapsules(
            in: characterRange,
            storage: storage,
            textContainer: textContainer,
            origin: origin
        )
        drawQuoteBars(
            in: characterRange,
            storage: storage,
            textContainer: textContainer,
            origin: origin
        )
        drawHeadingRules(
            in: characterRange,
            storage: storage,
            textContainer: textContainer,
            origin: origin
        )
        drawFrontMatterRules(
            in: characterRange,
            storage: storage,
            textContainer: textContainer,
            origin: origin
        )
        drawThematicBreaks(
            in: characterRange,
            storage: storage,
            textContainer: textContainer,
            origin: origin
        )
    }

    // MARK: - Decorations

    private func drawCodeBlocks(
        in characterRange: NSRange,
        storage: NSTextStorage,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) {
        enumerateAttributeRanges(.readerCodeBlock, in: characterRange, storage: storage) { range, _ in
            let fullRange = self.expandedRange(
                for: .readerCodeBlock,
                range: range,
                value: storage.attribute(.readerCodeBlock, at: range.location, effectiveRange: nil),
                storage: storage
            )
            let glyphRange = self.glyphRange(forCharacterRange: fullRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            guard var blockRect = self.textBox(forGlyphRange: glyphRange, origin: origin) else { return }

            let verticalPadding = self.theme.bodyFontSize * 1.25
            blockRect.origin.y -= verticalPadding
            blockRect.size.height += verticalPadding * 2

            self.theme.codeBackgroundColor.setFill()
            let path = NSBezierPath(
                roundedRect: blockRect,
                xRadius: 8,
                yRadius: 8
            )
            path.fill()

            self.theme.separatorColor.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawInlineCodeCapsules(
        in characterRange: NSRange,
        storage: NSTextStorage,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) {
        enumerateAttributeRanges(.readerCodeSpan, in: characterRange, storage: storage) { range, _ in
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            self.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(lineGlyphRange, glyphRange)
                guard intersection.length > 0 else { return }

                let inkRect = self.boundingRect(
                    forGlyphRange: intersection,
                    in: textContainer
                ).offsetBy(dx: origin.x, dy: origin.y)
                let lineRect = self.lineFragmentRect(
                    forGlyphAt: intersection.location,
                    effectiveRange: nil
                ).offsetBy(dx: origin.x, dy: origin.y)
                let baseline = lineRect.minY + self.location(forGlyphAt: intersection.location).y
                let characterIndex = self.characterIndexForGlyph(at: intersection.location)
                let font = self.font(at: characterIndex, in: storage)
                let horizontalPadding = font.pointSize * 0.25
                let verticalPadding = font.pointSize * 0.1
                let lastCharacterIndex = self.characterIndexForGlyph(
                    at: NSMaxRange(intersection) - 1
                )
                let trailingKern = (storage.attribute(
                    .kern,
                    at: lastCharacterIndex,
                    effectiveRange: nil
                ) as? CGFloat) ?? 0
                let capsule = NSRect(
                    x: inkRect.minX - horizontalPadding,
                    y: baseline - font.ascender - verticalPadding,
                    width: inkRect.width - trailingKern + horizontalPadding * 2,
                    height: font.ascender - font.descender + verticalPadding * 2
                )

                self.theme.codeBackgroundColor.setFill()
                let path = NSBezierPath(
                    roundedRect: capsule,
                    xRadius: 4,
                    yRadius: 4
                )
                path.fill()

                self.theme.separatorColor.withAlphaComponent(0.3).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    private func drawQuoteBars(
        in characterRange: NSRange,
        storage: NSTextStorage,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) {
        enumerateAttributeRanges(.readerBlockQuote, in: characterRange, storage: storage) { range, _ in
            let fullRange = self.expandedRange(
                for: .readerBlockQuote,
                range: range,
                value: storage.attribute(.readerBlockQuote, at: range.location, effectiveRange: nil),
                storage: storage
            )
            let glyphRange = self.glyphRange(forCharacterRange: fullRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            guard let quoteRect = self.textBox(forGlyphRange: glyphRange, origin: origin) else { return }

            let verticalPadding = self.theme.bodyFontSize * 0.25
            self.theme.separatorColor.setFill()
            NSRect(
                x: quoteRect.minX,
                y: quoteRect.minY - verticalPadding,
                width: 4,
                height: quoteRect.height + verticalPadding * 2
            ).fill()
        }
    }

    private func drawHeadingRules(
        in characterRange: NSRange,
        storage: NSTextStorage,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) {
        enumerateAttributeRanges(.readerHeadingLevel, in: characterRange, storage: storage) { range, value in
            let level = (value as? NSNumber)?.intValue ?? (value as? Int)
            guard let level, level <= 2 else { return }
            let fullRange = self.expandedRange(
                for: .readerHeadingLevel,
                range: range,
                value: value,
                storage: storage
            )
            let glyphRange = self.glyphRange(forCharacterRange: fullRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            self.drawRule(
                belowGlyphRange: glyphRange,
                offset: self.theme.bodyFontSize * 0.5,
                origin: origin
            )
        }
    }

    private func drawFrontMatterRules(
        in characterRange: NSRange,
        storage: NSTextStorage,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) {
        enumerateAttributeRanges(.readerFrontMatter, in: characterRange, storage: storage) { range, _ in
            let fullRange = self.expandedRange(
                for: .readerFrontMatter,
                range: range,
                value: storage.attribute(.readerFrontMatter, at: range.location, effectiveRange: nil),
                storage: storage
            )
            let glyphRange = self.glyphRange(forCharacterRange: fullRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            self.drawRule(
                belowGlyphRange: glyphRange,
                offset: self.theme.bodyFontSize * 0.2,
                origin: origin
            )
        }
    }

    private func drawThematicBreaks(
        in characterRange: NSRange,
        storage: NSTextStorage,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) {
        enumerateAttributeRanges(.readerThematicBreak, in: characterRange, storage: storage) { range, _ in
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            var lineRect: NSRect?
            self.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
                lineRect = rect
            }
            guard let lineRect else { return }
            let rect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            self.theme.separatorColor.setFill()
            NSRect(
                x: rect.minX,
                y: rect.midY - 1,
                width: rect.width,
                height: 2
            ).fill()
        }
    }

    // MARK: - Helpers

    private func textBox(forGlyphRange glyphRange: NSRange, origin: NSPoint) -> NSRect? {
        var box: NSRect?
        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, usedRect, _, _, _ in
            let rect = NSRect(
                x: lineRect.minX,
                y: usedRect.minY,
                width: lineRect.width,
                height: usedRect.height
            ).offsetBy(dx: origin.x, dy: origin.y)
            box = box.map { $0.union(rect) } ?? rect
        }
        return box
    }

    private func drawRule(belowGlyphRange glyphRange: NSRange, offset: CGFloat, origin: NSPoint) {
        var lastLine: NSRect?
        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, usedRect, _, _, _ in
            lastLine = NSRect(
                x: lineRect.minX,
                y: usedRect.minY,
                width: lineRect.width,
                height: usedRect.height
            )
        }
        guard let lastLine else { return }
        let rect = lastLine.offsetBy(dx: origin.x, dy: origin.y)
        let y = rect.maxY + offset - 0.5
        theme.separatorColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: y))
        path.line(to: NSPoint(x: rect.maxX, y: y))
        path.lineWidth = 1
        path.stroke()
    }

    private func enumerateAttributeRanges(
        _ key: NSAttributedString.Key,
        in range: NSRange,
        storage: NSTextStorage,
        body: (NSRange, Any) -> Void
    ) {
        storage.enumerateAttribute(key, in: range, options: []) { value, effectiveRange, _ in
            guard let value else { return }
            body(effectiveRange, value)
        }
    }

    private func expandedRange(
        for key: NSAttributedString.Key,
        range: NSRange,
        value: Any?,
        storage: NSTextStorage
    ) -> NSRange {
        guard let value else { return range }
        var expanded = range

        while expanded.location > 0,
              attributeValue(
                storage.attribute(key, at: expanded.location - 1, effectiveRange: nil),
                matches: value
              ) {
            expanded.location -= 1
            expanded.length += 1
        }

        while NSMaxRange(expanded) < storage.length,
              attributeValue(
                storage.attribute(key, at: NSMaxRange(expanded), effectiveRange: nil),
                matches: value
              ) {
            expanded.length += 1
        }
        return expanded
    }

    private func attributeValue(_ candidate: Any?, matches value: Any) -> Bool {
        guard let candidate else { return false }
        return (candidate as AnyObject).isEqual(value as AnyObject)
    }

    private func font(at location: Int, in storage: NSTextStorage) -> NSFont {
        (storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: theme.bodyFontSize)
    }
}
