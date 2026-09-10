import AppKit
import CoreText
import os
import QuartzCore

/// Identity of one reader character across two builds. A reveal only changes
/// which syntax is shown, so a character that exists in both builds carries
/// the same key in both; an edit that moves source text remaps the keys of
/// the old build first (`RevealTransitionSnapshot.remapped`).
enum RevealGlyphKey: Hashable {
    /// A character shown one-to-one for this source offset.
    case source(Int)
    /// The nth reader character of a substituted record (list bullet, image).
    case substituted(sourceLocation: Int, index: Int)
}

struct RevealMeasuredGlyph {
    let readerIndex: Int
    let box: MorphGlyphBox
}

/// Per-character geometry of the paragraphs a reveal change touches, in one
/// build of the reader, keyed for pairing with the other build.
struct RevealTransitionSnapshot {
    let glyphs: [RevealGlyphKey: RevealMeasuredGlyph]
    let measuredRanges: [NSRange]
    /// Glyphs an edit removed, under their keys in the old build: measured
    /// there, gone from the new build, so they only ever fade out.
    let deleted: [RevealGlyphKey: RevealMeasuredGlyph]

    init(
        glyphs: [RevealGlyphKey: RevealMeasuredGlyph],
        measuredRanges: [NSRange],
        deleted: [RevealGlyphKey: RevealMeasuredGlyph] = [:]
    ) {
        self.glyphs = glyphs
        self.measuredRanges = measuredRanges
        self.deleted = deleted
    }

    /// The same glyphs keyed by where an edit moves their source offsets, so
    /// a snapshot of the old text pairs with one of the new text. Glyphs whose
    /// offset maps to nil were removed by the edit and move to `deleted`. Two
    /// keys never land on the same new key for a wrap or unwrap; if they did,
    /// one glyph would be lost.
    func remapped(through newOffset: (Int) -> Int?) -> RevealTransitionSnapshot {
        var moved: [RevealGlyphKey: RevealMeasuredGlyph] = [:]
        moved.reserveCapacity(glyphs.count)
        var removed = deleted
        for (key, glyph) in glyphs {
            let newKey: RevealGlyphKey?
            switch key {
            case let .source(offset):
                newKey = newOffset(offset).map { .source($0) }
            case let .substituted(sourceLocation, index):
                newKey = newOffset(sourceLocation).map { .substituted(sourceLocation: $0, index: index) }
            }
            if let newKey {
                moved[newKey] = glyph
            } else {
                removed[key] = glyph
            }
        }
        return RevealTransitionSnapshot(glyphs: moved, measuredRanges: measuredRanges, deleted: removed)
    }
}

struct RevealTransitionEntry {
    let key: RevealGlyphKey
    /// The glyph as the new build draws it, or as the old one did for a
    /// disappearing glyph.
    let text: NSAttributedString
    let font: NSFont
    /// Position and old styling in the old build; nil for syntax that is appearing.
    let from: MorphGlyphBox?
    /// Position and new styling in the new build; nil for syntax that is disappearing.
    let to: MorphGlyphBox?
    /// The old and new builds style this glyph differently (regular to bold,
    /// say): the overlay fades a copy in the old styling out while the copy
    /// in the new styling fades in, both travelling together.
    let crossfades: Bool

    init(
        key: RevealGlyphKey,
        text: NSAttributedString,
        font: NSFont,
        from: MorphGlyphBox?,
        to: MorphGlyphBox?,
        crossfades: Bool = false
    ) {
        self.key = key
        self.text = text
        self.font = font
        self.from = from
        self.to = to
        self.crossfades = crossfades
    }

    var isMover: Bool { from != nil && to != nil }
}

struct RevealTransitionPlan {
    let entries: [RevealTransitionEntry]
    /// Reader ranges of the new build whose real glyphs the overlay stands in for.
    let hiddenRanges: [NSRange]
    /// Paired glyphs that change position.
    let moverCount: Int
    /// Paired glyphs that change styling, moving or not.
    let crossfadeCount: Int
    let fadeInCount: Int
    let fadeOutCount: Int
}

enum RevealTransitionError: Error {
    case overBudget(Int)
    case emptyRange
}

/// Plans the reveal animation: which paragraphs to measure, how to pair the
/// characters of the two builds, and which of them need a moving copy. The
/// cross-surface `MorphPlanner` is not reused; here both builds live in the
/// same text view with the same fonts, so pairing is by source identity alone.
enum RevealTransitionPlanner {
    static let characterBudget = 2_000
    /// Displacement below which a character stays where it is and keeps its
    /// real glyph instead of getting a layer.
    static let stillTolerance: CGFloat = 0.5

    /// The reader paragraphs holding the given source ranges, in the reader
    /// string of `map`. Overlapping or touching paragraphs merge; distant
    /// ones stay separate so a caret jump across the document only measures
    /// the two paragraphs that change.
    static func paragraphRanges(
        for sourceRanges: [NSRange],
        map: ReaderOffsetMap,
        string: NSString
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        for sourceRange in sourceRanges {
            let start = map.readerOffset(forSourceOffset: sourceRange.location)
            let end = map.readerOffset(forSourceOffset: NSMaxRange(sourceRange))
            let location = max(0, min(min(start, end), string.length))
            let length = max(0, min(abs(end - start), string.length - location))
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: length))
            guard paragraph.length > 0 else { continue }
            if let index = ranges.firstIndex(where: {
                NSMaxRange($0) >= paragraph.location && NSMaxRange(paragraph) >= $0.location
            }) {
                ranges[index] = NSUnionRange(ranges[index], paragraph)
            } else {
                ranges.append(paragraph)
            }
        }
        return ranges.sorted { $0.location < $1.location }
    }

    /// Measures the paragraphs holding `sourceRanges` in the text view's
    /// current layout and keys every character for pairing.
    static func snapshot(
        in textView: NSTextView,
        offsetMap: ReaderOffsetMap,
        sourceRanges: [NSRange]
    ) throws -> RevealTransitionSnapshot {
        guard let storage = textView.textStorage else {
            throw GlyphGeometryError.missingTextKitSurface
        }
        let string = storage.string as NSString
        let ranges = paragraphRanges(for: sourceRanges, map: offsetMap, string: string)
        guard !ranges.isEmpty else { throw RevealTransitionError.emptyRange }
        let total = ranges.reduce(0) { $0 + $1.length }
        guard total <= characterBudget else { throw RevealTransitionError.overBudget(total) }

        var glyphs: [RevealGlyphKey: RevealMeasuredGlyph] = [:]
        glyphs.reserveCapacity(total)
        for range in ranges {
            let geometry = try GlyphGeometry.measure(in: textView, characterRange: range)
            for (readerIndex, key) in keys(in: range, map: offsetMap) {
                guard let box = geometry.boxes[readerIndex] else { continue }
                // Attachments (images) have no glyph to copy; they hide and show.
                guard box.attributed.string.utf16.first != 0xFFFC else { continue }
                glyphs[key] = RevealMeasuredGlyph(readerIndex: readerIndex, box: box)
            }
        }
        return RevealTransitionSnapshot(glyphs: glyphs, measuredRanges: ranges)
    }

    /// Pairing keys for the reader characters in `range`. One-to-one records
    /// key by source offset; substituted records by their record and position.
    static func keys(in range: NSRange, map: ReaderOffsetMap) -> [(Int, RevealGlyphKey)] {
        var result: [(Int, RevealGlyphKey)] = []
        result.reserveCapacity(range.length)
        for record in map.records where record.readerRange.length > 0 {
            if record.readerRange.location >= NSMaxRange(range) { break }
            let intersection = NSIntersectionRange(record.readerRange, range)
            guard intersection.length > 0 else { continue }
            for readerIndex in intersection.location..<NSMaxRange(intersection) {
                let index = readerIndex - record.readerRange.location
                let key: RevealGlyphKey = record.isOneToOne
                    ? .source(record.sourceRange.location + index)
                    : .substituted(sourceLocation: record.sourceRange.location, index: index)
                result.append((readerIndex, key))
            }
        }
        return result
    }

    static func plan(
        before: RevealTransitionSnapshot,
        after: RevealTransitionSnapshot
    ) -> RevealTransitionPlan {
        var entries: [RevealTransitionEntry] = []
        var hiddenIndices: [Int] = []
        var movers = 0
        var crossfades = 0
        var fadeIns = 0
        var fadeOuts = 0

        for (key, new) in after.glyphs {
            if let old = before.glyphs[key] {
                let stayed = abs(old.box.x - new.box.x) <= stillTolerance
                    && abs(old.box.baseline - new.box.baseline) <= stillTolerance
                let restyled = !stylingMatches(old.box, new.box)
                guard !stayed || restyled else { continue }
                if !stayed { movers += 1 }
                if restyled { crossfades += 1 }
                entries.append(RevealTransitionEntry(
                    key: key,
                    text: new.box.attributed,
                    font: new.box.font,
                    from: old.box,
                    to: new.box,
                    crossfades: restyled
                ))
            } else {
                fadeIns += 1
                entries.append(RevealTransitionEntry(
                    key: key,
                    text: new.box.attributed,
                    font: new.box.font,
                    from: nil,
                    to: new.box
                ))
            }
            hiddenIndices.append(new.readerIndex)
        }
        for (key, old) in before.glyphs where after.glyphs[key] == nil {
            fadeOuts += 1
            entries.append(RevealTransitionEntry(
                key: key,
                text: old.box.attributed,
                font: old.box.font,
                from: old.box,
                to: nil
            ))
        }
        for (key, old) in before.deleted {
            fadeOuts += 1
            entries.append(RevealTransitionEntry(
                key: key,
                text: old.box.attributed,
                font: old.box.font,
                from: old.box,
                to: nil
            ))
        }

        return RevealTransitionPlan(
            entries: entries,
            hiddenRanges: coalesce(hiddenIndices),
            moverCount: movers,
            crossfadeCount: crossfades,
            fadeInCount: fadeIns,
            fadeOutCount: fadeOuts
        )
    }

    /// Whether two measurements of a glyph draw it the same way. Only the
    /// font and the strikethrough count: a colour or kerning change alone
    /// is not worth a second layer.
    static func stylingMatches(_ old: MorphGlyphBox, _ new: MorphGlyphBox) -> Bool {
        guard old.font == new.font else { return false }
        let oldStrike = old.attributed.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int ?? 0
        let newStrike = new.attributed.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int ?? 0
        return oldStrike == newStrike
    }

    static func coalesce(_ indices: [Int]) -> [NSRange] {
        var ranges: [NSRange] = []
        for index in indices.sorted() {
            if let last = ranges.last, NSMaxRange(last) == index {
                ranges[ranges.count - 1] = NSRange(location: last.location, length: last.length + 1)
            } else {
                ranges.append(NSRange(location: index, length: 1))
            }
        }
        return ranges
    }
}

/// A transparent subview of the reader text view that animates copies of the
/// glyphs a reveal change moves, shows, or hides. It sits inside the text
/// view so it scrolls with the text; its frame is the bounding box of the
/// animated glyphs, converted from the text view's flipped coordinates. The
/// real glyphs under it are hidden through `ReaderLayoutManager` until the
/// animation ends or is interrupted.
final class RevealTransitionOverlay: NSView {
    struct ActiveEntry {
        let entry: RevealTransitionEntry
        /// The copy in the entry's styling: the new one, or the old one for
        /// a disappearing glyph.
        let layer: MorphGlyphLayer
        /// For a crossfade, the copy in the old styling that fades out.
        let fromLayer: MorphGlyphLayer?
        let from: CGPoint
        let to: CGPoint
    }

    private static let log = Logger(subsystem: "plus.lost.Markfops", category: "formatted-editing")
    static let duration: CFTimeInterval = 0.2

    /// Human-readable record of the last run. Read by tests.
    private(set) var lastOutcome = "idle"
    /// Layers of the run in progress with their start and end. Read by tests.
    private(set) var activeEntries: [ActiveEntry] = []
    var isRunning: Bool { runningGeneration != nil }

    private var generation = 0
    private var runningGeneration: Int?
    private weak var hidingLayoutManager: ReaderLayoutManager?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("RevealTransitionOverlay does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    private func record(_ outcome: String) {
        lastOutcome = outcome
        Self.log.info("reveal transition: \(outcome, privacy: .public)")
    }

    /// Starts the animation for `plan` inside `textView`. Any earlier run is
    /// finished first.
    func run(_ plan: RevealTransitionPlan, in textView: NSTextView) {
        finishImmediately()
        guard !plan.entries.isEmpty else {
            record("skipped: nothing moved")
            return
        }
        guard textView.window != nil else {
            record("skipped: no window")
            return
        }

        textView.wantsLayer = true
        frame = Self.frame(for: plan.entries)
        if superview !== textView {
            removeFromSuperview()
            textView.addSubview(self)
        }
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale

        generation &+= 1
        let current = generation
        runningGeneration = current

        let moveTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.82, 0.2, 1)
        let fadeTiming = CAMediaTimingFunction(name: .easeOut)
        var active: [ActiveEntry] = []
        active.reserveCapacity(plan.entries.count)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            self?.finish(generation: current)
        }
        func move(_ glyph: CALayer, from start: CGPoint, to end: CGPoint) {
            guard start != end else { return }
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: start)
            move.toValue = NSValue(point: end)
            move.duration = Self.duration
            move.timingFunction = moveTiming
            glyph.position = end
            glyph.add(move, forKey: "revealPosition")
        }
        func fade(_ glyph: CALayer, to target: Float) {
            guard glyph.opacity != target else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = glyph.opacity
            fade.toValue = target
            fade.duration = Self.duration
            fade.timingFunction = fadeTiming
            glyph.opacity = target
            glyph.add(fade, forKey: "revealOpacity")
        }

        for entry in plan.entries {
            let width = (entry.to ?? entry.from)?.width ?? 0
            let glyph = MorphGlyphLayer(text: entry.text, font: entry.font, width: width, scale: scale)
            let from = entry.from.map { position(for: $0, font: entry.font, in: textView) }
            let to = entry.to.map { position(for: $0, font: entry.font, in: textView) }
            let start = from ?? to ?? .zero
            let end = to ?? from ?? .zero
            glyph.position = start
            // A crossfading glyph starts invisible under its old-styling copy.
            glyph.opacity = entry.from == nil || entry.crossfades ? 0 : 1
            layer?.addSublayer(glyph)

            var fromLayer: MorphGlyphLayer?
            if entry.crossfades, let oldBox = entry.from, let newBox = entry.to {
                let old = MorphGlyphLayer(text: oldBox.attributed, font: oldBox.font, width: oldBox.width, scale: scale)
                old.position = position(for: oldBox, font: oldBox.font, in: textView)
                old.opacity = 1
                layer?.addSublayer(old)
                // Travels with the new copy, keeping its own baseline offset.
                let oldEnd = position(x: newBox.x, baseline: newBox.baseline, font: oldBox.font, in: textView)
                move(old, from: old.position, to: oldEnd)
                fade(old, to: 0)
                fromLayer = old
            }

            if from != nil, to != nil {
                move(glyph, from: start, to: end)
            }
            fade(glyph, to: entry.to == nil ? 0 : 1)
            active.append(ActiveEntry(entry: entry, layer: glyph, fromLayer: fromLayer, from: start, to: end))
        }
        CATransaction.commit()

        activeEntries = active
        if let layoutManager = textView.layoutManager as? ReaderLayoutManager {
            hidingLayoutManager = layoutManager
            layoutManager.hiddenCharacterRanges = plan.hiddenRanges
        }
        record(
            "animating: \(active.count) layers (\(plan.moverCount) moving, \(plan.crossfadeCount) restyling, \(plan.fadeInCount) appearing, \(plan.fadeOutCount) disappearing), hiding \(plan.hiddenRanges.count) ranges"
        )
    }

    /// Jumps to the end state: layers gone, real glyphs shown.
    func finishImmediately() {
        guard runningGeneration != nil || superview != nil else { return }
        generation &+= 1
        clear()
    }

    private func finish(generation completed: Int) {
        guard runningGeneration == completed else { return }
        clear()
    }

    private func clear() {
        runningGeneration = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.removeAllAnimations()
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
        activeEntries.removeAll()
        hidingLayoutManager?.hiddenCharacterRanges = []
        hidingLayoutManager = nil
        removeFromSuperview()
    }

    /// The bounding box of every glyph the plan touches, in the text view's
    /// flipped coordinates, with a little slack for glyph overhang.
    private static func frame(for entries: [RevealTransitionEntry]) -> CGRect {
        var union: CGRect?
        for entry in entries {
            for box in [entry.from, entry.to].compactMap({ $0 }) {
                let rect = CGRect(
                    x: box.x,
                    y: box.baseline - box.font.ascender,
                    width: max(1, box.width),
                    height: box.font.ascender - box.font.descender
                )
                union = union.map { $0.union(rect) } ?? rect
            }
        }
        return (union ?? .zero).insetBy(dx: -8, dy: -8)
    }

    /// The layer origin (bottom-left, anchor zero) for a box, converted from
    /// the text view's flipped coordinates into this view's.
    private func position(for box: MorphGlyphBox, font: NSFont, in textView: NSTextView) -> CGPoint {
        position(x: box.x, baseline: box.baseline, font: font, in: textView)
    }

    private func position(x: CGFloat, baseline: CGFloat, font: NSFont, in textView: NSTextView) -> CGPoint {
        let baselinePoint = convert(NSPoint(x: x, y: baseline), from: textView)
        return CGPoint(x: baselinePoint.x, y: baselinePoint.y + font.descender)
    }
}

extension MorphGlyphLayer {
    convenience init(text: NSAttributedString, font: NSFont, width: CGFloat, scale: CGFloat) {
        self.init()
        self.text = text
        descent = -font.descender
        bounds = CGRect(
            x: 0,
            y: 0,
            width: max(2, ceil(width) + 2),
            height: max(2, ceil(font.ascender - font.descender) + 2)
        )
        anchorPoint = .zero
        contentsScale = scale
        setNeedsDisplay()
    }
}
