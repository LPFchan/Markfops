import AppKit

final class ReaderLayoutManager: NSLayoutManager {
    var theme: ReaderTheme = .default
    /// Whole-view glyph opacity, driven by the mode morph while its layers move.
    var morphGlyphOpacity: CGFloat = 1
    /// Character ranges whose glyphs are not drawn while a reveal transition
    /// animates copies of them. Independent of `morphGlyphOpacity`.
    var hiddenCharacterRanges: [NSRange] = [] {
        didSet {
            for range in oldValue + hiddenCharacterRanges where range.length > 0 {
                invalidateDisplay(forCharacterRange: range)
            }
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

        guard glyphsToShow.length > 0,
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

            var blockRect: NSRect?
            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                let rect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
                blockRect = blockRect.map { $0.union(rect) } ?? rect
            }
            guard var blockRect else { return }

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
                // The last code character carries a kern that makes room for the
                // capsule's right padding. The bounding rect includes that kern, so
                // it must come off again or the capsule swallows the following space.
                let lastCharacterIndex = self.characterIndexForGlyph(
                    at: NSMaxRange(intersection) - 1
                )
                let trailingKern = (storage.attribute(
                    .kern,
                    at: lastCharacterIndex,
                    effectiveRange: nil
                ) as? CGFloat) ?? 0
                // Layout coordinates are flipped: the ascender sits above the baseline
                // at smaller y, the descender below it at larger y.
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

            var quoteRect: NSRect?
            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                let rect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
                quoteRect = quoteRect.map { $0.union(rect) } ?? rect
            }
            guard let quoteRect else { return }

            self.theme.separatorColor.setFill()
            NSRect(
                x: quoteRect.minX,
                y: quoteRect.minY,
                width: 4,
                height: quoteRect.height
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

            var lastLine: NSRect?
            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                lastLine = lineRect
            }
            guard let lastLine else { return }
            let rect = lastLine.offsetBy(dx: origin.x, dy: origin.y)
            self.theme.separatorColor.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY - 0.5))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 0.5))
            path.lineWidth = 1
            path.stroke()
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

            var lastLine: NSRect?
            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                lastLine = lineRect
            }
            guard let lastLine else { return }
            let rect = lastLine.offsetBy(dx: origin.x, dy: origin.y)
            self.theme.separatorColor.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY - 0.5))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 0.5))
            path.lineWidth = 1
            path.stroke()
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
