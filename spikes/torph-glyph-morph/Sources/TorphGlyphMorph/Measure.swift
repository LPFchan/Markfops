import AppKit

/// Where one character sits after layout. Coordinates are y-up, origin at the bottom-left of the text block.
struct GlyphBox {
    let x: CGFloat
    let baseline: CGFloat
    let width: CGFloat
    let font: NSFont
    let attributed: NSAttributedString
}

struct MeasuredLayout {
    /// Presentation character index -> box. Newlines have no box.
    let boxes: [Int: GlyphBox]
    let height: CGFloat
    let duration: Duration
}

/// Lays the presentation out with TextKit 1 (the same stack Markfops' editor uses) and reads back
/// every character's position. This is the whole measurement cost the morph depends on.
func measure(_ presentation: Presentation, width: CGFloat) -> MeasuredLayout {
    var boxes: [Int: GlyphBox] = [:]
    var height: CGFloat = 0
    let duration = ContinuousClock().measure {
        let storage = NSTextStorage(attributedString: presentation.attributed)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        height = ceil(layoutManager.usedRect(for: container).height)

        let string = storage.string as NSString
        for charIndex in 0..<string.length {
            if string.character(at: charIndex) == 0x0A { continue }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            let bounds = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
            let single = storage.attributedSubstring(from: NSRange(location: charIndex, length: 1))
            let font = single.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? Style.sourceFont
            boxes[charIndex] = GlyphBox(
                x: lineRect.minX + location.x,
                baseline: height - (lineRect.minY + location.y),
                width: bounds.width,
                font: font,
                attributed: single
            )
        }
    }
    return MeasuredLayout(boxes: boxes, height: height, duration: duration)
}
