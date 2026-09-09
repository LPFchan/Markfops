import AppKit

struct MorphGlyphBox {
    let x: CGFloat
    let baseline: CGFloat
    let width: CGFloat
    let font: NSFont
    let attributed: NSAttributedString

    var rect: CGRect {
        CGRect(
            x: x,
            y: baseline + font.descender,
            width: width,
            height: font.ascender - font.descender
        )
    }
}

struct MeasuredGlyphGeometry {
    let boxes: [Int: MorphGlyphBox]
    let requestedRange: NSRange
    let laidOutRange: NSRange
}

enum GlyphGeometryError: Error {
    case missingTextKitSurface
    case invalidCharacterRange
    case noLayoutForRange
}

enum GlyphGeometry {
    /// Reads TextKit 1 geometry for a bounded character range. The line range is
    /// expanded before layout so a character at either edge has a complete line
    /// fragment, while the rest of a long document remains lazy.
    static func measure(
        in textView: NSTextView,
        characterRange: NSRange
    ) throws -> MeasuredGlyphGeometry {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let storage = textView.textStorage else {
            throw GlyphGeometryError.missingTextKitSurface
        }

        let source = storage.string as NSString
        let boundedLocation = max(0, min(characterRange.location, source.length))
        let boundedLength = max(
            0,
            min(characterRange.length, source.length - boundedLocation)
        )
        let requestedRange = NSRange(location: boundedLocation, length: boundedLength)
        guard requestedRange.length > 0 else {
            throw GlyphGeometryError.invalidCharacterRange
        }

        let laidOutRange = source.lineRange(for: requestedRange)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: laidOutRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else {
            throw GlyphGeometryError.noLayoutForRange
        }
        layoutManager.ensureLayout(forGlyphRange: glyphRange)

        let origin = textView.textContainerOrigin
        var boxes: [Int: MorphGlyphBox] = [:]
        boxes.reserveCapacity(requestedRange.length)
        let numberOfGlyphs = layoutManager.numberOfGlyphs

        // One line-fragment lookup per line, reused for every glyph on it.
        var lineRect = CGRect.zero
        var lineGlyphRange = NSRange(location: 0, length: 0)

        for characterIndex in requestedRange.location..<NSMaxRange(requestedRange) {
            let character = source.character(at: characterIndex)
            guard character != 0x0A, character != 0x0D else { continue }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            guard glyphIndex < numberOfGlyphs else { continue }

            if !NSLocationInRange(glyphIndex, lineGlyphRange) {
                lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &lineGlyphRange
                )
            }
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            let xInContainer = lineRect.minX + location.x
            let width: CGFloat
            let nextGlyph = glyphIndex + 1
            if nextGlyph < NSMaxRange(lineGlyphRange) {
                width = max(0, lineRect.minX + layoutManager.location(forGlyphAt: nextGlyph).x - xInContainer)
            } else {
                width = max(0, lineRect.maxX - xInContainer)
            }
            let single = storage.attributedSubstring(
                from: NSRange(location: characterIndex, length: 1)
            )
            let font = single.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

            boxes[characterIndex] = MorphGlyphBox(
                x: origin.x + xInContainer,
                baseline: origin.y + lineRect.minY + location.y,
                width: max(0, width),
                font: font,
                attributed: single
            )
        }

        return MeasuredGlyphGeometry(
            boxes: boxes,
            requestedRange: requestedRange,
            laidOutRange: laidOutRange
        )
    }

    /// Finds the characters touched by the visible viewport and a symmetric
    /// half-viewport margin. The returned range is in the text view's source
    /// presentation, not in the text container's local coordinates.
    static func visibleCharacterRange(
        in textView: NSTextView,
        marginFraction: CGFloat = 0.5
    ) throws -> NSRange {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView,
              textView.textStorage != nil else {
            throw GlyphGeometryError.missingTextKitSurface
        }

        let visibleRect = scrollView.contentView.documentVisibleRect
        let margin = max(0, visibleRect.height * marginFraction)
        let targetRectInView = visibleRect.insetBy(dx: 0, dy: -margin)
        let origin = textView.textContainerOrigin
        let targetRect = targetRectInView.offsetBy(dx: -origin.x, dy: -origin.y)
        layoutManager.ensureLayout(forBoundingRect: targetRect, in: textContainer)

        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: targetRect,
            in: textContainer
        )
        guard glyphRange.length > 0 else {
            throw GlyphGeometryError.noLayoutForRange
        }
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        guard characterRange.length > 0 else {
            throw GlyphGeometryError.noLayoutForRange
        }
        return characterRange
    }

}
