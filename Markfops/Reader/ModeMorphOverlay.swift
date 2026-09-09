import AppKit
import CoreText
import os
import QuartzCore
import SwiftUI

struct ModeMorphRequest {
    let id: UUID
    let documentID: UUID
    let from: EditMode
    let to: EditMode
    let anchor: ViewportAnchorSync.Anchor

    init(
        documentID: UUID,
        from: EditMode,
        to: EditMode,
        anchor: ViewportAnchorSync.Anchor
    ) {
        self.id = UUID()
        self.documentID = documentID
        self.from = from
        self.to = to
        self.anchor = anchor
    }
}

final class MorphGlyphLayer: CALayer {
    var text: NSAttributedString?
    var descent: CGFloat = 0

    override func draw(in context: CGContext) {
        guard let text else { return }
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, context)
    }
}

struct ModeMorphOverlayRepresentable: NSViewRepresentable {
    let request: ModeMorphRequest
    let document: Document
    let themeKey: String
    let editorBridge: EditorBridge
    let readerBridge: ReaderBridge
    let onFinished: (UUID) -> Void

    func makeNSView(context: Context) -> ModeMorphOverlay {
        let view = ModeMorphOverlay(
            document: document,
            themeKey: themeKey,
            editorBridge: editorBridge,
            readerBridge: readerBridge,
            onFinished: onFinished
        )
        view.request = request
        return view
    }

    func updateNSView(_ nsView: ModeMorphOverlay, context: Context) {
        nsView.document = document
        nsView.themeKey = themeKey
        nsView.request = request
    }

    static func dismantleNSView(_ nsView: ModeMorphOverlay, coordinator: ()) {
        nsView.finishImmediatelyForCurrentRequest()
    }
}

/// A transparent, non-interactive layer tree that moves the measured glyphs.
/// Core Animation owns both the position interpolation and the short glyph
/// crossfade; this view does no display-link or timer work.
final class ModeMorphOverlay: NSView {
    var document: Document
    var themeKey: String
    let editorBridge: EditorBridge
    let readerBridge: ReaderBridge
    private let onFinished: (UUID) -> Void

    var request: ModeMorphRequest? {
        didSet {
            guard request?.id != oldValue?.id, let request else { return }
            cancelRunningMorph()
            pendingRequestGeneration &+= 1
            let generation = pendingRequestGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.pendingRequestGeneration == generation,
                      self.request?.id == request.id else { return }
                self.start(request)
            }
        }
    }

    private struct ActiveRenderable {
        let renderable: MorphRenderable
        let fromLayer: MorphGlyphLayer?
        let toLayer: MorphGlyphLayer?
    }

    private static let log = Logger(subsystem: "plus.lost.Markfops", category: "morph")
    /// Human-readable record of what the last request did. Read by tests.
    private(set) var lastOutcome = "idle"

    private func record(_ outcome: String) {
        lastOutcome = outcome
        Self.log.info("morph: \(outcome, privacy: .public)")
    }

    private var activeRequestID: UUID?
    private var activeRequest: ModeMorphRequest?
    private var activeRenderables: [ActiveRenderable] = []
    private var pendingRequestGeneration = 0
    private let animationDuration: CFTimeInterval = 0.36
    private let swapWindow: CFTimeInterval = 0.45

    init(
        document: Document,
        themeKey: String,
        editorBridge: EditorBridge,
        readerBridge: ReaderBridge,
        onFinished: @escaping (UUID) -> Void
    ) {
        self.document = document
        self.themeKey = themeKey
        self.editorBridge = editorBridge
        self.readerBridge = readerBridge
        self.onFinished = onFinished
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("ModeMorphOverlay does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var acceptsFirstResponder: Bool { false }

    func finishImmediatelyForCurrentRequest() {
        pendingRequestGeneration &+= 1
        if let activeRequest {
            finishSurfaceState(for: activeRequest.to)
        } else if let request {
            finishSurfaceState(for: request.to)
        } else {
            finishSurfaceState(for: document.mode)
        }
        clearLayers()
        activeRequestID = nil
        activeRequest = nil
    }

    private func start(_ request: ModeMorphRequest) {
        guard activeRequestID != request.id else { return }
        guard ModeMorphPolicy.canMorph(sourceLength: document.textStorage.length) else {
            record("skipped: policy (length \(document.textStorage.length), reduceMotion \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))")
            finishInstantly(request)
            return
        }

        restoreIncomingViewport(request)
        readerBridge.prepareForMorph(themeKey: themeKey)

        guard let editorTextView = editorBridge.morphTextView(),
              let editorScrollView = editorBridge.morphScrollView(),
              let readerTextView = readerBridge.morphTextView(),
              let readerScrollView = readerBridge.morphScrollView(),
              let presentation = readerBridge.morphPresentation() else {
            record("skipped: missing surfaces editorTV=\(editorBridge.morphTextView() != nil) editorSV=\(editorBridge.morphScrollView() != nil) readerTV=\(readerBridge.morphTextView() != nil) readerSV=\(readerBridge.morphScrollView() != nil) presentation=\(readerBridge.morphPresentation() != nil)")
            finishInstantly(request)
            return
        }

        let editorEndpoint = MorphEndpoint(
            kind: .editor,
            textView: editorTextView,
            scrollView: editorScrollView
        )
        let readerEndpoint = MorphEndpoint(
            kind: .reader,
            textView: readerTextView,
            scrollView: readerScrollView,
            offsetMap: presentation.offsetMap
        )
        let fromEndpoint = request.from == .edit ? editorEndpoint : readerEndpoint
        let toEndpoint = request.to == .edit ? editorEndpoint : readerEndpoint

        do {
            let plan = try MorphPlanner.build(
                from: fromEndpoint,
                to: toEndpoint,
                sourceText: document.rawText,
                overlayView: self
            )
            guard !plan.renderables.isEmpty else {
                record("skipped: empty plan")
                finishInstantly(request)
                return
            }
            record("animating: \(plan.renderables.count) renderables, overlay frame \(NSStringFromRect(frame)), window \(window != nil)")
            activeRequestID = request.id
            activeRequest = request
            prepareSurfaceLayers(
                request: request,
                editorTextView: editorTextView,
                editorScrollView: editorScrollView,
                readerTextView: readerTextView,
                readerScrollView: readerScrollView
            )
            buildLayers(for: plan)
            animate(request: request, readerTextView: readerTextView)
        } catch {
            record("skipped: planner threw \(error) editorVisible=\(NSStringFromRect(editorScrollView.contentView.documentVisibleRect)) readerVisible=\(NSStringFromRect(readerScrollView.contentView.documentVisibleRect)) readerFrame=\(NSStringFromRect(readerTextView.frame)) readerLen=\(readerTextView.textStorage?.length ?? -1)")
            finishInstantly(request)
        }
    }

    private func restoreIncomingViewport(_ request: ModeMorphRequest) {
        switch request.to {
        case .edit:
            if let sourceLine = request.anchor.sourceLine,
               editorBridge.scrollToSourceLineCentered(sourceLine) {
                return
            }
            editorBridge.scrollToRatio(request.anchor.ratio)
        case .preview:
            readerBridge.setPendingViewportRestore(
                sourceLine: request.anchor.sourceLine,
                ratio: request.anchor.ratio,
                applyImmediately: true
            )
        }
    }

    private func prepareSurfaceLayers(
        request: ModeMorphRequest,
        editorTextView: MarkdownNSTextView,
        editorScrollView: NSScrollView,
        readerTextView: ReaderNSTextView,
        readerScrollView: NSScrollView
    ) {
        editorTextView.wantsLayer = true
        readerTextView.wantsLayer = true
        editorScrollView.drawsBackground = true
        editorScrollView.backgroundColor = editorTextView.backgroundColor
        readerScrollView.drawsBackground = true
        readerScrollView.backgroundColor = readerTextView.backgroundColor

        editorTextView.layer?.removeAllAnimations()
        readerTextView.layer?.removeAllAnimations()
        editorTextView.layer?.opacity = 0
        readerTextView.layer?.opacity = request.from == .preview ? 1 : 0
        (readerTextView.layoutManager as? ReaderLayoutManager)?.morphGlyphOpacity = 0
        readerTextView.needsDisplay = true
    }

    private func buildLayers(for plan: MorphPlan) {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        activeRenderables.removeAll(keepingCapacity: true)
        activeRenderables.reserveCapacity(plan.renderables.count)

        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        layer?.contentsScale = scale

        for renderable in plan.renderables {
            let fromLayer = renderable.fromBox.flatMap {
                makeGlyphLayer(box: $0, text: renderable.fromText, scale: scale)
            }
            let toLayer = renderable.toBox.flatMap {
                makeGlyphLayer(box: $0, text: renderable.toText, scale: scale)
            }
            if let fromLayer { layer?.addSublayer(fromLayer) }
            if let toLayer { layer?.addSublayer(toLayer) }

            setInitialState(
                for: renderable,
                fromLayer: fromLayer,
                toLayer: toLayer
            )
            activeRenderables.append(ActiveRenderable(
                renderable: renderable,
                fromLayer: fromLayer,
                toLayer: toLayer
            ))
        }
    }

    private func makeGlyphLayer(
        box: MorphGlyphBox,
        text: NSAttributedString?,
        scale: CGFloat
    ) -> MorphGlyphLayer? {
        guard let text else { return nil }
        let glyph = MorphGlyphLayer()
        glyph.text = text
        glyph.descent = -box.font.descender
        glyph.bounds = CGRect(
            x: 0,
            y: 0,
            width: max(2, ceil(box.width) + 2),
            height: max(2, ceil(box.font.ascender - box.font.descender) + 2)
        )
        glyph.anchorPoint = .zero
        glyph.contentsScale = scale
        glyph.setNeedsDisplay()
        return glyph
    }

    private func position(for box: MorphGlyphBox) -> CGPoint {
        CGPoint(x: box.x, y: box.baseline + box.font.descender)
    }

    private func pairPosition(
        x: CGFloat,
        baseline: CGFloat,
        layerFont: NSFont
    ) -> CGPoint {
        CGPoint(x: x, y: baseline + layerFont.descender)
    }

    private func setInitialState(
        for renderable: MorphRenderable,
        fromLayer: MorphGlyphLayer?,
        toLayer: MorphGlyphLayer?
    ) {
        switch (renderable.fromBox, renderable.toBox) {
        case let (from?, to?):
            fromLayer?.position = pairPosition(
                x: from.x,
                baseline: from.baseline,
                layerFont: from.font
            )
            toLayer?.position = pairPosition(
                x: from.x,
                baseline: from.baseline,
                layerFont: to.font
            )
            fromLayer?.opacity = 1
            toLayer?.opacity = 0
        case let (from?, nil):
            fromLayer?.position = position(for: from)
            fromLayer?.opacity = 1
        case let (nil, to?):
            toLayer?.position = position(for: to)
            toLayer?.opacity = 0
        case (nil, nil):
            break
        }
    }

    private func setEndState(for active: ActiveRenderable) {
        switch (active.renderable.fromBox, active.renderable.toBox) {
        case let (from?, to?):
            active.fromLayer?.position = pairPosition(
                x: to.x,
                baseline: to.baseline,
                layerFont: from.font
            )
            active.toLayer?.position = pairPosition(
                x: to.x,
                baseline: to.baseline,
                layerFont: to.font
            )
        case let (from?, nil):
            active.fromLayer?.position = position(for: from)
        case let (nil, to?):
            active.toLayer?.position = position(for: to)
        case (nil, nil):
            break
        }
        active.fromLayer?.opacity = 0
        active.toLayer?.opacity = 1
    }

    /// Explicit animations only. These layers were added to the tree in this same
    /// run-loop pass, so Core Animation would give them no implicit animation:
    /// every glyph would appear at its destination and the completion block would
    /// fire at once. Explicit from/to values animate regardless of layer age.
    private func animate(
        request: ModeMorphRequest,
        readerTextView: ReaderNSTextView
    ) {
        let targetReaderOpacity: Float = request.to == .preview ? 1 : 0
        let moveTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.82, 0.2, 1)
        let fadeTiming = CAMediaTimingFunction(name: .easeOut)
        let fadeDuration = animationDuration * swapWindow

        func move(_ layer: CALayer?, to end: CGPoint) {
            guard let layer else { return }
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: layer.position)
            animation.toValue = NSValue(point: end)
            animation.duration = animationDuration
            animation.timingFunction = moveTiming
            layer.position = end
            layer.add(animation, forKey: "morphPosition")
        }

        func fade(_ layer: CALayer?, to end: Float) {
            guard let layer, layer.opacity != end else { return }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = layer.opacity
            animation.toValue = end
            animation.duration = fadeDuration
            animation.timingFunction = fadeTiming
            layer.opacity = end
            layer.add(animation, forKey: "morphOpacity")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            self?.finish(request)
        }
        for active in activeRenderables {
            if let from = active.renderable.fromBox,
               let to = active.renderable.toBox {
                move(active.fromLayer, to: pairPosition(
                    x: to.x,
                    baseline: to.baseline,
                    layerFont: from.font
                ))
                move(active.toLayer, to: pairPosition(
                    x: to.x,
                    baseline: to.baseline,
                    layerFont: to.font
                ))
            }
            fade(active.fromLayer, to: 0)
            fade(active.toLayer, to: 1)
        }
        fade(readerTextView.layer, to: targetReaderOpacity)
        CATransaction.commit()
    }

    private func finish(_ request: ModeMorphRequest) {
        guard activeRequestID == request.id else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for active in activeRenderables {
            setEndState(for: active)
        }
        CATransaction.commit()
        finishSurfaceState(for: request.to)
        clearLayers()
        activeRequestID = nil
        activeRequest = nil
        onFinished(request.id)
    }

    private func finishInstantly(_ request: ModeMorphRequest) {
        cancelRunningMorph()
        finishSurfaceState(for: request.to)
        onFinished(request.id)
    }

    private func finishSurfaceState(for mode: EditMode) {
        Self.resetSurfaceState(editorBridge: editorBridge, readerBridge: readerBridge, mode: mode)
    }

    /// Puts both text surfaces back in their resting state for a mode. Called at the
    /// end of a morph, and by the container when a switch happens without one, so
    /// a text layer hidden by an earlier morph never stays hidden.
    static func resetSurfaceState(editorBridge: EditorBridge, readerBridge: ReaderBridge, mode: EditMode) {
        guard let editorTextView = editorBridge.morphTextView(),
              let editorScrollView = editorBridge.morphScrollView(),
              let readerTextView = readerBridge.morphTextView(),
              let readerScrollView = readerBridge.morphScrollView() else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        editorTextView.wantsLayer = true
        readerTextView.wantsLayer = true
        editorTextView.layer?.removeAllAnimations()
        readerTextView.layer?.removeAllAnimations()
        editorTextView.layer?.opacity = mode == .edit ? 1 : 0
        readerTextView.layer?.opacity = mode == .preview ? 1 : 0
        (readerTextView.layoutManager as? ReaderLayoutManager)?.morphGlyphOpacity = 1
        readerTextView.needsDisplay = true
        editorTextView.needsDisplay = true
        editorScrollView.drawsBackground = true
        editorScrollView.backgroundColor = editorTextView.backgroundColor
        readerScrollView.drawsBackground = true
        readerScrollView.backgroundColor = readerTextView.backgroundColor
        CATransaction.commit()
    }

    private func cancelRunningMorph() {
        guard let request = activeRequest, activeRequestID == request.id else {
            clearLayers()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for active in activeRenderables {
            setEndState(for: active)
        }
        CATransaction.commit()
        finishSurfaceState(for: request.to)
        clearLayers()
        activeRequestID = nil
        activeRequest = nil
    }

    private func clearLayers() {
        layer?.removeAllAnimations()
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        activeRenderables.removeAll(keepingCapacity: true)
    }
}
