import AppKit
import CoreText
import os
import QuartzCore

/// Identity of one reader character across two builds of the same source
/// text. A reveal only changes which syntax is shown, so a character that
/// exists in both builds carries the same key in both.
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
}

struct RevealTransitionEntry {
    let key: RevealGlyphKey
    let text: NSAttributedString
    let font: NSFont
    /// Position in the old build; nil for syntax that is appearing.
    let from: MorphGlyphBox?
    /// Position in the new build; nil for syntax that is disappearing.
    let to: MorphGlyphBox?

    var isMover: Bool { from != nil && to != nil }
}

struct RevealTransitionPlan {
    let entries: [RevealTransitionEntry]
    /// Reader ranges of the new build whose real glyphs the overlay stands in for.
    let hiddenRanges: [NSRange]
    let moverCount: Int
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
        var fadeIns = 0
        var fadeOuts = 0

        for (key, new) in after.glyphs {
            if let old = before.glyphs[key] {
                let stayed = abs(old.box.x - new.box.x) <= stillTolerance
                    && abs(old.box.baseline - new.box.baseline) <= stillTolerance
                guard !stayed else { continue }
                movers += 1
                entries.append(RevealTransitionEntry(
                    key: key,
                    text: new.box.attributed,
                    font: new.box.font,
                    from: old.box,
                    to: new.box
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

        return RevealTransitionPlan(
            entries: entries,
            hiddenRanges: coalesce(hiddenIndices),
            moverCount: movers,
            fadeInCount: fadeIns,
            fadeOutCount: fadeOuts
        )
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
        let layer: MorphGlyphLayer
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
        for entry in plan.entries {
            let glyph = MorphGlyphLayer(reveal: entry, scale: scale)
            let from = entry.from.map { position(for: $0, font: entry.font, in: textView) }
            let to = entry.to.map { position(for: $0, font: entry.font, in: textView) }
            let start = from ?? to ?? .zero
            let end = to ?? from ?? .zero
            glyph.position = start
            glyph.opacity = entry.from == nil ? 0 : 1
            layer?.addSublayer(glyph)

            if from != nil, to != nil, start != end {
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(point: start)
                move.toValue = NSValue(point: end)
                move.duration = Self.duration
                move.timingFunction = moveTiming
                glyph.position = end
                glyph.add(move, forKey: "revealPosition")
            }
            let targetOpacity: Float = entry.to == nil ? 0 : 1
            if glyph.opacity != targetOpacity {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = glyph.opacity
                fade.toValue = targetOpacity
                fade.duration = Self.duration
                fade.timingFunction = fadeTiming
                glyph.opacity = targetOpacity
                glyph.add(fade, forKey: "revealOpacity")
            }
            active.append(ActiveEntry(entry: entry, layer: glyph, from: start, to: end))
        }
        CATransaction.commit()

        activeEntries = active
        if let layoutManager = textView.layoutManager as? ReaderLayoutManager {
            hidingLayoutManager = layoutManager
            layoutManager.hiddenCharacterRanges = plan.hiddenRanges
        }
        record(
            "animating: \(active.count) layers (\(plan.moverCount) moving, \(plan.fadeInCount) appearing, \(plan.fadeOutCount) disappearing), hiding \(plan.hiddenRanges.count) ranges"
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
        let baselinePoint = convert(NSPoint(x: box.x, y: box.baseline), from: textView)
        return CGPoint(x: baselinePoint.x, y: baselinePoint.y + font.descender)
    }
}

extension MorphGlyphLayer {
    convenience init(reveal entry: RevealTransitionEntry, scale: CGFloat) {
        self.init()
        text = entry.text
        descent = -entry.font.descender
        let width = (entry.to ?? entry.from)?.width ?? 0
        bounds = CGRect(
            x: 0,
            y: 0,
            width: max(2, ceil(width) + 2),
            height: max(2, ceil(entry.font.ascender - entry.font.descender) + 2)
        )
        anchorPoint = .zero
        contentsScale = scale
        setNeedsDisplay()
    }
}
