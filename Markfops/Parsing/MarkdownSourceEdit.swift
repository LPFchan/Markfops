import Foundation

/// One ranged replacement of the Markdown source, with the selection to show
/// afterwards and where each old character lands, so formatted mode can pair
/// the glyphs of the old text with the new and animate between them. Shared
/// by the wrap and heading commands and applied by either mode.
struct MarkdownSourceEdit: Equatable {
    /// A piece of `range` that survives the edit and where it lands in the
    /// new text.
    struct Kept: Equatable {
        let old: NSRange
        let newLocation: Int
    }

    /// Source range to replace.
    let range: NSRange
    let replacement: String
    /// Source selection to show afterwards.
    let selection: NSRange
    /// The parts of `range` the replacement keeps, in order. Text outside
    /// `range` is kept as a whole and only shifts.
    let kept: [Kept]

    /// The replacement's range in the new text.
    var newRange: NSRange {
        NSRange(location: range.location, length: (replacement as NSString).length)
    }

    /// Where the character at an old source offset sits in the new text,
    /// or nil when the edit removed it.
    func newOffset(forOldOffset offset: Int) -> Int? {
        if offset < range.location { return offset }
        if offset >= NSMaxRange(range) {
            return offset + (replacement as NSString).length - range.length
        }
        for piece in kept where NSLocationInRange(offset, piece.old) {
            return piece.newLocation + offset - piece.old.location
        }
        return nil
    }
}
