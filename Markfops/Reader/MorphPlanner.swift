import AppKit

enum MorphPresentationKind: Equatable {
    case editor
    case reader
}

struct MorphEndpoint {
    let kind: MorphPresentationKind
    let textView: NSTextView
    let scrollView: NSScrollView
    let offsetMap: ReaderOffsetMap?

    init(
        kind: MorphPresentationKind,
        textView: NSTextView,
        scrollView: NSScrollView,
        offsetMap: ReaderOffsetMap? = nil
    ) {
        self.kind = kind
        self.textView = textView
        self.scrollView = scrollView
        self.offsetMap = offsetMap
    }
}

enum MorphRenderableKind: Equatable {
    case glyph
    case word
}

struct MorphRenderable {
    let kind: MorphRenderableKind
    let sourceOffsets: [Int]
    let fromBox: MorphGlyphBox?
    let toBox: MorphGlyphBox?
    let fromText: NSAttributedString?
    let toText: NSAttributedString?

    var layerCount: Int {
        (fromBox == nil ? 0 : 1) + (toBox == nil ? 0 : 1)
    }
}

struct MorphPlan {
    let sourceRange: NSRange
    let pairedCharacterCount: Int
    let sourceOnlyCount: Int
    let destinationOnlyCount: Int
    let renderables: [MorphRenderable]
    let usedWordFallback: Bool

    var layerCount: Int {
        renderables.reduce(0) { $0 + $1.layerCount }
    }
}

enum ModeMorphPolicy {
    static func canMorph(sourceLength: Int) -> Bool {
        sourceLength > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

enum MorphPlanner {
    static let pairedCharacterBudget = 1_500
    static let layerBudget = pairedCharacterBudget * 2
    private static let centerGlyphBudget = 300

    static func build(
        from: MorphEndpoint,
        to: MorphEndpoint,
        sourceText: String,
        overlayView: NSView
    ) throws -> MorphPlan {
        let source = sourceText as NSString
        let signpostID = TabSwitchProfiler.beginMorphPlan(characterCount: source.length)
        var pairedCount = 0
        var layerCount = 0
        defer {
            TabSwitchProfiler.endMorphPlan(
                signpostID: signpostID,
                pairedCharacters: pairedCount,
                layerCount: layerCount
            )
        }

        guard source.length > 0, from.kind != to.kind else {
            throw GlyphGeometryError.invalidCharacterRange
        }

        let visiblePresentationRange = try GlyphGeometry.visibleCharacterRange(
            in: from.textView
        )
        let sourceRange = try sourceRange(
            for: visiblePresentationRange,
            endpoint: from,
            source: source
        )
        let fromRange = presentationRange(for: sourceRange, endpoint: from)
        let toRange = presentationRange(for: sourceRange, endpoint: to)

        let fromGeometry = try GlyphGeometry.measure(
            in: from.textView,
            characterRange: fromRange
        )
        let toGeometry = try GlyphGeometry.measure(
            in: to.textView,
            characterRange: toRange
        )
        let fromBoxes = convertedBoxes(
            fromGeometry.boxes,
            from: from.textView,
            to: overlayView
        )
        let toBoxes = convertedBoxes(
            toGeometry.boxes,
            from: to.textView,
            to: overlayView
        )

        let entries = makeEntries(
            in: sourceRange,
            source: source,
            from: from,
            to: to,
            fromBoxes: fromBoxes,
            toBoxes: toBoxes
        )
        pairedCount = entries.reduce(into: 0) { count, entry in
            if entry.fromBox != nil, entry.toBox != nil {
                count += 1
            }
        }
        guard pairedCount > 0 || !entries.isEmpty else {
            throw GlyphGeometryError.noLayoutForRange
        }

        let usedWordFallback = pairedCount > pairedCharacterBudget
        let renderables: [MorphRenderable]
        if usedWordFallback {
            renderables = boundedFallbackRenderables(
                entries: entries,
                sourceRange: sourceRange
            )
        } else {
            renderables = entries.map(glyphRenderable)
        }
        layerCount = renderables.reduce(0) { $0 + $1.layerCount }

        let sourceOnlyCount = entries.filter { $0.fromBox != nil && $0.toBox == nil }.count
        let destinationOnlyCount = entries.filter { $0.fromBox == nil && $0.toBox != nil }.count
        return MorphPlan(
            sourceRange: sourceRange,
            pairedCharacterCount: pairedCount,
            sourceOnlyCount: sourceOnlyCount,
            destinationOnlyCount: destinationOnlyCount,
            renderables: renderables,
            usedWordFallback: usedWordFallback
        )
    }

    private struct Entry {
        let sourceOffset: Int
        let sourceCharacter: unichar
        let fromBox: MorphGlyphBox?
        let toBox: MorphGlyphBox?
        let fromText: NSAttributedString?
        let toText: NSAttributedString?
    }

    private static func sourceRange(
        for presentationRange: NSRange,
        endpoint: MorphEndpoint,
        source: NSString
    ) throws -> NSRange {
        let rawRange: NSRange
        switch endpoint.kind {
        case .editor:
            rawRange = presentationRange
        case .reader:
            guard let offsetMap = endpoint.offsetMap else {
                throw GlyphGeometryError.missingTextKitSurface
            }
            let start = offsetMap.sourceOffset(forReaderOffset: presentationRange.location)
            let end = offsetMap.sourceOffset(forReaderOffset: NSMaxRange(presentationRange))
            let location = min(start, end)
            let maxEnd = max(start, end)
            rawRange = NSRange(
                location: location,
                length: max(1, maxEnd - location)
            )
        }

        let boundedLocation = max(0, min(rawRange.location, source.length))
        let boundedEnd = max(
            boundedLocation,
            min(NSMaxRange(rawRange), source.length)
        )
        let bounded = NSRange(
            location: boundedLocation,
            length: boundedEnd - boundedLocation
        )
        guard bounded.length > 0 else {
            throw GlyphGeometryError.noLayoutForRange
        }
        return source.lineRange(for: bounded)
    }

    private static func presentationRange(
        for sourceRange: NSRange,
        endpoint: MorphEndpoint
    ) -> NSRange {
        switch endpoint.kind {
        case .editor:
            return sourceRange
        case .reader:
            guard let offsetMap = endpoint.offsetMap else {
                return NSRange(location: 0, length: 0)
            }
            let start = offsetMap.readerOffset(forSourceOffset: sourceRange.location)
            let end = offsetMap.readerOffset(forSourceOffset: NSMaxRange(sourceRange))
            return NSRange(
                location: min(start, end),
                length: abs(end - start)
            )
        }
    }

    /// Converts boxes into the overlay's coordinate space. The views only differ by
    /// translation and a possible y flip, so two converted points define the map and
    /// the thousands of per-box conversions become arithmetic.
    private static func convertedBoxes(
        _ boxes: [Int: MorphGlyphBox],
        from textView: NSTextView,
        to overlayView: NSView
    ) -> [Int: MorphGlyphBox] {
        let origin = overlayView.convert(NSPoint.zero, from: textView)
        let unit = overlayView.convert(NSPoint(x: 1, y: 1), from: textView)
        let scaleX = unit.x - origin.x
        let scaleY = unit.y - origin.y
        return boxes.mapValues { box in
            MorphGlyphBox(
                x: origin.x + box.x * scaleX,
                baseline: origin.y + box.baseline * scaleY,
                width: abs(box.width * scaleX),
                font: box.font,
                attributed: box.attributed
            )
        }
    }

    private static func makeEntries(
        in sourceRange: NSRange,
        source: NSString,
        from: MorphEndpoint,
        to: MorphEndpoint,
        fromBoxes: [Int: MorphGlyphBox],
        toBoxes: [Int: MorphGlyphBox]
    ) -> [Entry] {
        guard let offsetMap = (from.offsetMap ?? to.offsetMap) else {
            return (sourceRange.location..<NSMaxRange(sourceRange)).compactMap { sourceOffset in
                let fromBox = fromBoxes[sourceOffset]
                let toBox = toBoxes[sourceOffset]
                guard fromBox != nil || toBox != nil else { return nil }
                return Entry(
                    sourceOffset: sourceOffset,
                    sourceCharacter: source.character(at: sourceOffset),
                    fromBox: fromBox,
                    toBox: toBox,
                    fromText: fromBox?.attributed,
                    toText: toBox?.attributed
                )
            }
        }

        var entries: [Entry] = []
        var handledSourceOffsets = Set<Int>()
        var handledReaderOffsets = Set<Int>()

        for record in offsetMap.records {
            let sourceIntersection = NSIntersectionRange(record.sourceRange, sourceRange)
            guard sourceIntersection.length > 0 else { continue }

            let isCharacterToCharacter = !record.isSubstitution
                && record.sourceRange.length == record.readerRange.length

            if isCharacterToCharacter {
                for sourceOffset in sourceIntersection.location..<NSMaxRange(sourceIntersection) {
                    guard handledSourceOffsets.insert(sourceOffset).inserted else { continue }
                    let readerOffset = record.readerRange.location
                        + sourceOffset - record.sourceRange.location
                    guard handledReaderOffsets.insert(readerOffset).inserted else { continue }
                    appendEntry(
                        to: &entries,
                        sourceOffset: sourceOffset,
                        source: source,
                        from: from,
                        to: to,
                        readerOffset: readerOffset,
                        fromBoxes: fromBoxes,
                        toBoxes: toBoxes
                    )
                }
                continue
            }

            for sourceOffset in sourceIntersection.location..<NSMaxRange(sourceIntersection) {
                guard handledSourceOffsets.insert(sourceOffset).inserted else { continue }
                let fromBox = from.kind == .editor ? fromBoxes[sourceOffset] : nil
                let toBox = to.kind == .editor ? toBoxes[sourceOffset] : nil
                guard fromBox != nil || toBox != nil else { continue }
                entries.append(Entry(
                    sourceOffset: sourceOffset,
                    sourceCharacter: source.character(at: sourceOffset),
                    fromBox: fromBox,
                    toBox: toBox,
                    fromText: fromBox?.attributed,
                    toText: toBox?.attributed
                ))
            }

            guard record.readerRange.length > 0 else { continue }
            for readerOffset in record.readerRange.location..<NSMaxRange(record.readerRange) {
                guard handledReaderOffsets.insert(readerOffset).inserted else { continue }
                let fromBox = from.kind == .reader ? fromBoxes[readerOffset] : nil
                let toBox = to.kind == .reader ? toBoxes[readerOffset] : nil
                guard fromBox != nil || toBox != nil else { continue }
                entries.append(Entry(
                    sourceOffset: record.sourceRange.location,
                    sourceCharacter: source.character(at: record.sourceRange.location),
                    fromBox: fromBox,
                    toBox: toBox,
                    fromText: fromBox?.attributed,
                    toText: toBox?.attributed
                ))
            }
        }

        return entries.sorted {
            if $0.sourceOffset != $1.sourceOffset {
                return $0.sourceOffset < $1.sourceOffset
            }
            if $0.fromBox == nil { return false }
            return $1.fromBox == nil
        }
    }

    private static func appendEntry(
        to entries: inout [Entry],
        sourceOffset: Int,
        source: NSString,
        from: MorphEndpoint,
        to: MorphEndpoint,
        readerOffset: Int,
        fromBoxes: [Int: MorphGlyphBox],
        toBoxes: [Int: MorphGlyphBox]
    ) {
        let fromBox = from.kind == .editor
            ? fromBoxes[sourceOffset]
            : fromBoxes[readerOffset]
        let toBox = to.kind == .editor
            ? toBoxes[sourceOffset]
            : toBoxes[readerOffset]
        guard fromBox != nil || toBox != nil else { return }
        entries.append(Entry(
            sourceOffset: sourceOffset,
            sourceCharacter: source.character(at: sourceOffset),
            fromBox: fromBox,
            toBox: toBox,
            fromText: fromBox?.attributed,
            toText: toBox?.attributed
        ))
    }

    private static func glyphRenderable(_ entry: Entry) -> MorphRenderable {
        MorphRenderable(
            kind: .glyph,
            sourceOffsets: [entry.sourceOffset],
            fromBox: entry.fromBox,
            toBox: entry.toBox,
            fromText: entry.fromText,
            toText: entry.toText
        )
    }

    private static func boundedFallbackRenderables(
        entries: [Entry],
        sourceRange: NSRange
    ) -> [MorphRenderable] {
        var centerCandidates = entries.filter(isGroupablePair)
        let center = sourceRange.location + sourceRange.length / 2
        centerCandidates.sort {
            abs($0.sourceOffset - center) < abs($1.sourceOffset - center)
        }

        var centerGlyphCount = min(centerGlyphBudget, centerCandidates.count)
        var renderables = fallbackRenderables(
            entries: entries,
            centerGlyphOffsets: Set(centerCandidates.prefix(centerGlyphCount).map(\.sourceOffset))
        )
        while renderables.reduce(0, { $0 + $1.layerCount }) > layerBudget,
              centerGlyphCount > 0 {
            centerGlyphCount = max(0, centerGlyphCount - 50)
            renderables = fallbackRenderables(
                entries: entries,
                centerGlyphOffsets: Set(centerCandidates.prefix(centerGlyphCount).map(\.sourceOffset))
            )
        }

        if renderables.reduce(0, { $0 + $1.layerCount }) > layerBudget {
            renderables = coalesceWordRenderables(renderables)
        }
        return renderables
    }

    private static func fallbackRenderables(
        entries: [Entry],
        centerGlyphOffsets: Set<Int>
    ) -> [MorphRenderable] {
        var result: [MorphRenderable] = []
        var wordEntries: [Entry] = []

        func flushWord() {
            guard !wordEntries.isEmpty else { return }
            result.append(wordRenderable(wordEntries))
            wordEntries.removeAll(keepingCapacity: true)
        }

        for entry in entries {
            guard entry.fromBox != nil, entry.toBox != nil else {
                flushWord()
                result.append(glyphRenderable(entry))
                continue
            }

            guard isGroupablePair(entry), !centerGlyphOffsets.contains(entry.sourceOffset) else {
                flushWord()
                result.append(glyphRenderable(entry))
                continue
            }

            if let last = wordEntries.last,
               last.sourceOffset + 1 == entry.sourceOffset,
               sameWordRun(last, entry) {
                wordEntries.append(entry)
            } else {
                flushWord()
                wordEntries = [entry]
            }
        }
        flushWord()
        return result
    }

    private static func isGroupablePair(_ entry: Entry) -> Bool {
        guard let fromText = entry.fromText, let toText = entry.toText else { return false }
        guard fromText.attribute(.attachment, at: 0, effectiveRange: nil) == nil,
              toText.attribute(.attachment, at: 0, effectiveRange: nil) == nil else {
            return false
        }
        guard toText.attribute(.readerCodeSpan, at: 0, effectiveRange: nil) == nil,
              toText.attribute(.readerCodeBlock, at: 0, effectiveRange: nil) == nil else {
            return false
        }
        return entry.sourceCharacter != 0x0A && entry.sourceCharacter != 0x0D
    }

    private static func sameWordRun(_ lhs: Entry, _ rhs: Entry) -> Bool {
        guard let lhsFrom = lhs.fromBox,
              let rhsFrom = rhs.fromBox,
              let lhsTo = lhs.toBox,
              let rhsTo = rhs.toBox else { return false }
        return abs(lhsFrom.baseline - rhsFrom.baseline) < 0.5
            && abs(lhsTo.baseline - rhsTo.baseline) < 0.5
            && (lhsFrom.font === rhsFrom.font || lhsFrom.font.isEqual(rhsFrom.font))
            && (lhsTo.font === rhsTo.font || lhsTo.font.isEqual(rhsTo.font))
    }

    private static func wordRenderable(_ entries: [Entry]) -> MorphRenderable {
        let fromEntries = entries.compactMap { $0.fromBox }
        let toEntries = entries.compactMap { $0.toBox }
        let fromText = combinedText(entries.compactMap { $0.fromText })
        let toText = combinedText(entries.compactMap { $0.toText })
        return MorphRenderable(
            kind: .word,
            sourceOffsets: entries.map(\.sourceOffset),
            fromBox: combinedBox(fromEntries, text: fromText),
            toBox: combinedBox(toEntries, text: toText),
            fromText: fromText,
            toText: toText
        )
    }

    private static func combinedText(_ parts: [NSAttributedString]) -> NSAttributedString? {
        guard !parts.isEmpty else { return nil }
        let result = NSMutableAttributedString()
        for part in parts { result.append(part) }
        return result
    }

    private static func combinedBox(
        _ boxes: [MorphGlyphBox],
        text: NSAttributedString?
    ) -> MorphGlyphBox? {
        guard let first = boxes.first, let text else { return nil }
        let minX = boxes.map(\.x).min() ?? first.x
        let maxX = boxes.map { $0.x + $0.width }.max() ?? first.x
        return MorphGlyphBox(
            x: minX,
            baseline: first.baseline,
            width: max(0, maxX - minX),
            font: first.font,
            attributed: text
        )
    }

    private static func coalesceWordRenderables(
        _ renderables: [MorphRenderable]
    ) -> [MorphRenderable] {
        var result = renderables
        while result.reduce(0, { $0 + $1.layerCount }) > layerBudget {
            guard let index = result.indices.first(where: { index in
                index + 1 < result.count
                    && result[index].kind == .word
                    && result[index + 1].kind == .word
            }) else { break }
            let lhs = result[index]
            let rhs = result[index + 1]
            let merged = MorphRenderable(
                kind: .word,
                sourceOffsets: lhs.sourceOffsets + rhs.sourceOffsets,
                fromBox: combinedBox(
                    [lhs.fromBox, rhs.fromBox].compactMap { $0 },
                    text: combinedText([lhs.fromText, rhs.fromText].compactMap { $0 })
                ),
                toBox: combinedBox(
                    [lhs.toBox, rhs.toBox].compactMap { $0 },
                    text: combinedText([lhs.toText, rhs.toText].compactMap { $0 })
                ),
                fromText: combinedText([lhs.fromText, rhs.fromText].compactMap { $0 }),
                toText: combinedText([lhs.toText, rhs.toText].compactMap { $0 })
            )
            result.replaceSubrange(index...(index + 1), with: [merged])
        }
        return result
    }
}
