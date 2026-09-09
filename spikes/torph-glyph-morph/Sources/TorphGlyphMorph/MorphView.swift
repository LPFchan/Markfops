import AppKit
import QuartzCore

/// One character drawn once into a bitmap. Moving it afterwards is compositor work only.
final class GlyphLayer: CALayer {
    var text: NSAttributedString?
    var descent: CGFloat = 0

    override func draw(in ctx: CGContext) {
        guard let text else { return }
        let line = CTLineCreateWithAttributedString(text)
        ctx.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, ctx)
    }
}

struct FrameStats {
    var frames = 0
    var applyMicros: [Double] = []
    var intervalsMillis: [Double] = []
    var note: String?

    var summary: String {
        if let note { return note }
        guard !applyMicros.isEmpty else { return "no frames" }
        let meanApply = applyMicros.reduce(0, +) / Double(applyMicros.count)
        let maxApply = applyMicros.max() ?? 0
        let sortedIntervals = intervalsMillis.sorted()
        let medianInterval = sortedIntervals.isEmpty ? 0 : sortedIntervals[sortedIntervals.count / 2]
        let maxInterval = sortedIntervals.last ?? 0
        let dropped = intervalsMillis.filter { $0 > medianInterval * 1.5 }.count
        return String(
            format: "display link: %d frames · apply mean %.0f µs, max %.0f µs · frame median %.1f ms, max %.1f ms · %d long gaps",
            frames, meanApply, maxApply, medianInterval, maxInterval, dropped
        )
    }
}

func micros(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1e6 + Double(duration.components.attoseconds) / 1e12
}

/// Shows the same source characters in two presentations and slides every character from one to the other.
final class MorphView: NSView {
    private struct Pair {
        let kind: CharKind
        let from: GlyphBox?
        let to: GlyphBox?
        let fromLayer: GlyphLayer?
        let toLayer: GlyphLayer?
    }

    private struct Capsule {
        let from: CGRect
        let to: CGRect
        let layer: CALayer
    }

    private let chars: [SourceChar]
    private let source: MeasuredLayout
    private let rendered: MeasuredLayout
    private let sourceIndexMap: [Int?]
    private let renderedIndexMap: [Int?]
    private var pairs: [Pair] = []
    private var capsules: [Capsule] = []
    private let inset: CGFloat = 24

    private var progressBacking: CGFloat = 0

    /// 0 = source presentation, 1 = rendered presentation. Setting it applies the state without animation.
    var progress: CGFloat {
        get { progressBacking }
        set {
            progressBacking = newValue
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyPositions(newValue)
            applyOpacities(newValue)
            CATransaction.commit()
            onProgressChange?(newValue)
        }
    }
    var onProgressChange: ((CGFloat) -> Void)?
    var onAnimationEnd: ((FrameStats) -> Void)?

    private var displayLink: CADisplayLink?
    private var animationStart: CFTimeInterval = 0
    private var animationFrom: CGFloat = 0
    private var animationTo: CGFloat = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var stats = FrameStats()
    let animationDuration: CFTimeInterval = 0.42
    /// The glyph swap finishes at this fraction of the animation; positions keep moving to the end.
    let swapWindow: CGFloat = 0.45

    init(chars: [SourceChar], source: MeasuredLayout, rendered: MeasuredLayout) {
        self.chars = chars
        self.source = source
        self.rendered = rendered
        self.sourceIndexMap = sourcePresentation(chars).indexMap
        self.renderedIndexMap = renderedPresentation(chars).indexMap
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Style.backgroundColor.cgColor
        buildLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeGlyphLayer(_ box: GlyphBox) -> GlyphLayer {
        let glyph = GlyphLayer()
        glyph.text = box.attributed
        glyph.descent = -box.font.descender
        glyph.bounds = CGRect(x: 0, y: 0, width: ceil(box.width) + 2, height: ceil(box.font.ascender - box.font.descender))
        glyph.anchorPoint = .zero
        glyph.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        glyph.setNeedsDisplay()
        layer?.addSublayer(glyph)
        return glyph
    }

    private func buildLayers() {
        // Capsules go underneath the glyphs, so add them first.
        var runStart: Int?
        for index in 0...chars.count {
            let isCode = index < chars.count && chars[index].kind == .code
            if isCode, runStart == nil { runStart = index }
            if !isCode, let start = runStart {
                addCapsule(for: start..<index)
                runStart = nil
            }
        }

        for (index, char) in chars.enumerated() {
            if char.character == "\n" { continue }
            let from = sourceIndexMap[index].flatMap { source.boxes[$0] }
            let to = renderedIndexMap[index].flatMap { rendered.boxes[$0] }
            pairs.append(Pair(
                kind: char.kind,
                from: from,
                to: to,
                fromLayer: from.map(makeGlyphLayer),
                toLayer: to.map(makeGlyphLayer)
            ))
        }
    }

    private func addCapsule(for run: Range<Int>) {
        // In the source view the capsule hugs the backticks too, so it visibly shrinks onto the code.
        let sourceRange = (run.lowerBound - 1)..<(run.upperBound + 1)
        let fromBoxes = sourceRange.compactMap { sourceIndexMap[$0].flatMap { source.boxes[$0] } }
        let toBoxes = run.compactMap { renderedIndexMap[$0].flatMap { rendered.boxes[$0] } }
        guard let from = union(fromBoxes, padX: 0, padY: 1),
              let to = union(toBoxes, padX: 3, padY: 2) else { return }
        let layer = CALayer()
        layer.backgroundColor = Style.capsuleColor.cgColor
        layer.cornerRadius = 5
        layer.anchorPoint = .zero
        self.layer?.addSublayer(layer)
        capsules.append(Capsule(from: from, to: to, layer: layer))
    }

    private func union(_ boxes: [GlyphBox], padX: CGFloat, padY: CGFloat) -> CGRect? {
        guard let first = boxes.first else { return nil }
        var rect = first.rect
        for box in boxes.dropFirst() { rect = rect.union(box.rect) }
        return rect.insetBy(dx: -padX, dy: -padY)
    }

    /// Converts a layout-local point to view coordinates, top-aligning both presentations.
    private func origin(for layout: MeasuredLayout) -> CGPoint {
        CGPoint(x: inset, y: bounds.height - inset - layout.height)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t), width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }

    override func layout() {
        super.layout()
        progress = progress + 0
    }

    // MARK: Model state at a given progress

    private func applyPositions(_ t: CGFloat) {
        let sourceOrigin = origin(for: source)
        let renderedOrigin = origin(for: rendered)

        for capsule in capsules {
            let from = capsule.from.offsetBy(dx: sourceOrigin.x, dy: sourceOrigin.y)
            let to = capsule.to.offsetBy(dx: renderedOrigin.x, dy: renderedOrigin.y)
            let rect = lerp(from, to, t)
            capsule.layer.bounds = CGRect(origin: .zero, size: rect.size)
            capsule.layer.position = rect.origin
        }

        for pair in pairs {
            switch (pair.from, pair.to) {
            case let (from?, to?):
                let x = lerp(from.x + sourceOrigin.x, to.x + renderedOrigin.x, t)
                let baseline = lerp(from.baseline + sourceOrigin.y, to.baseline + renderedOrigin.y, t)
                pair.fromLayer?.position = CGPoint(x: x, y: baseline + from.font.descender)
                pair.toLayer?.position = CGPoint(x: x, y: baseline + to.font.descender)
            case let (from?, nil):
                pair.fromLayer?.position = CGPoint(x: from.x + sourceOrigin.x, y: from.baseline + sourceOrigin.y + from.font.descender)
            case let (nil, to?):
                pair.toLayer?.position = CGPoint(x: to.x + renderedOrigin.x, y: to.baseline + renderedOrigin.y + to.font.descender)
            case (nil, nil):
                break
            }
        }
    }

    private func applyOpacities(_ t: CGFloat) {
        let swap = Float(max(0, min(1, t / swapWindow)))
        for capsule in capsules { capsule.layer.opacity = swap }
        for pair in pairs {
            pair.fromLayer?.opacity = 1 - swap
            pair.toLayer?.opacity = swap
        }
    }

    // MARK: Animation, driven per frame from the main thread

    func animate(to target: CGFloat) {
        stopAnimation()
        animationFrom = progress
        animationTo = target
        animationStart = CACurrentMediaTime()
        lastFrameTime = animationStart
        stats = FrameStats()
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = now - animationStart
        let u = CGFloat(min(1, elapsed / animationDuration))
        let eased = 1 - pow(1 - u, 3)
        let applyDuration = ContinuousClock().measure {
            progress = animationFrom + (animationTo - animationFrom) * eased
        }
        stats.frames += 1
        stats.applyMicros.append(micros(applyDuration))
        if stats.frames > 1 {
            stats.intervalsMillis.append((now - lastFrameTime) * 1000)
        }
        lastFrameTime = now
        if u >= 1 {
            link.invalidate()
            displayLink = nil
            onAnimationEnd?(stats)
        }
    }

    // MARK: Animation, handed to Core Animation in one shot

    /// Sets the end state once and lets the render server interpolate. The main thread pays only the setup.
    /// The glyph crossfade is a shorter transaction than the slide, matching the display-link path.
    func animateWithCoreAnimation(to target: CGFloat) {
        stopAnimation()
        let setup = ContinuousClock().measure {
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            CATransaction.setAnimationDuration(animationDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.82, 0.2, 1))
            applyPositions(target)
            CATransaction.commit()

            CATransaction.begin()
            CATransaction.setDisableActions(false)
            CATransaction.setAnimationDuration(animationDuration * swapWindow)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            applyOpacities(target)
            CATransaction.commit()
        }
        // Record the end state without re-applying it, which would cancel the animations.
        progressBacking = target
        onProgressChange?(target)
        let note = String(format: "core animation: setup %.0f µs for %d layers, then zero main-thread work per frame", micros(setup), layerCount)
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            self?.onAnimationEnd?(FrameStats(note: note))
        }
    }

    func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    var layerCount: Int { layer?.sublayers?.count ?? 0 }

    /// Renders the current layer tree to a PNG. Used by `--snapshot`.
    func writeSnapshot(to url: URL) throws {
        let scale: CGFloat = 2
        let size = bounds.size
        guard let ctx = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.scaleBy(x: scale, y: scale)
        layer?.sublayers?.forEach { $0.displayIfNeeded() }
        layer?.render(in: ctx)
        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url)
    }
}

extension GlyphBox {
    var rect: CGRect {
        CGRect(x: x, y: baseline + font.descender, width: width, height: font.ascender - font.descender)
    }
}
