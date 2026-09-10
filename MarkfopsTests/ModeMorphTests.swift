import AppKit
import SwiftUI
import XCTest
@testable import Markfops

final class ModeMorphTests: XCTestCase {
    func testGeometryReadsLinesKoreanAndDisablesReaderLigatures() throws {
        let text = "first line\n한국어 fi"
        let editor = makeSurface(
            text: NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                    .ligature: 0,
                ]
            ),
            size: NSSize(width: 500, height: 240)
        )
        defer { editor.window.orderOut(nil) }

        let geometry = try GlyphGeometry.measure(
            in: editor.textView,
            characterRange: NSRange(location: 0, length: (text as NSString).length)
        )
        let firstLine = (0..<5).compactMap { geometry.boxes[$0] }
        XCTAssertEqual(firstLine.count, 5)
        XCTAssertTrue(zip(firstLine, firstLine.dropFirst()).allSatisfy { $0.x < $1.x })

        let koreanIndex = (text as NSString).range(of: "한").location
        XCTAssertGreaterThan(try XCTUnwrap(geometry.boxes[koreanIndex]).width, 0)

        let secondLineIndex = (text as NSString).range(of: "한국어").location
        XCTAssertGreaterThan(
            try XCTUnwrap(geometry.boxes[secondLineIndex]).baseline,
            try XCTUnwrap(geometry.boxes[0]).baseline
        )

        let readerPresentation = ReaderPresentation.build(
            text: "fi",
            sourceMap: MarkdownSourceMap.parse("fi")
        )
        XCTAssertEqual(
            (readerPresentation.attributedString.attribute(
                .ligature,
                at: 0,
                effectiveRange: nil
            ) as? NSNumber)?.intValue,
            0
        )
        let reader = makeSurface(
            text: readerPresentation.attributedString,
            size: NSSize(width: 500, height: 120)
        )
        defer { reader.window.orderOut(nil) }
        let readerGeometry = try GlyphGeometry.measure(
            in: reader.textView,
            characterRange: NSRange(location: 0, length: 2)
        )
        XCTAssertNotNil(readerGeometry.boxes[0])
        XCTAssertNotNil(readerGeometry.boxes[1])
        XCTAssertLessThan(
            try XCTUnwrap(readerGeometry.boxes[0]).x,
            try XCTUnwrap(readerGeometry.boxes[1]).x
        )
    }

    func testPairingKeepsContentAndSeparatesSyntaxAndSubstitutions() throws {
        let text = "# Heading\n\n`code`\n- item\n> quote"
        let canvas = makeCanvas(text: text, size: NSSize(width: 700, height: 500))
        defer { canvas.window.orderOut(nil) }

        let editorEndpoint = MorphEndpoint(
            kind: .editor,
            textView: canvas.editor.textView,
            scrollView: canvas.editor.scrollView
        )
        let readerEndpoint = MorphEndpoint(
            kind: .reader,
            textView: canvas.reader.textView,
            scrollView: canvas.reader.scrollView,
            offsetMap: canvas.readerPresentation.offsetMap
        )
        let plan = try MorphPlanner.build(
            from: editorEndpoint,
            to: readerEndpoint,
            sourceText: text,
            overlayView: canvas.overlay
        )

        XCTAssertGreaterThan(plan.pairedCharacterCount, 0)
        XCTAssertGreaterThan(plan.sourceOnlyCount, 0)
        XCTAssertGreaterThan(plan.destinationOnlyCount, 0)

        let pairedOffsets = Set(plan.renderables.filter {
            $0.fromBox != nil && $0.toBox != nil
        }.flatMap(\.sourceOffsets))
        let sourceOnlyOffsets = Set(plan.renderables.filter {
            $0.fromBox != nil && $0.toBox == nil
        }.flatMap(\.sourceOffsets))
        let destinationOnlyOffsets = Set(plan.renderables.filter {
            $0.fromBox == nil && $0.toBox != nil
        }.flatMap(\.sourceOffsets))
        let source = text as NSString
        for record in canvas.readerPresentation.offsetMap.records {
            let intersection = NSIntersectionRange(record.sourceRange, plan.sourceRange)
            guard intersection.length > 0 else { continue }
            if record.role == .syntax && record.readerRange.length == 0 {
                for offset in intersection.location..<NSMaxRange(intersection) {
                    guard source.character(at: offset) != 0x0A else { continue }
                    XCTAssertTrue(
                        sourceOnlyOffsets.contains(offset),
                        "missing omitted syntax offset \(offset)"
                    )
                }
            }
            if record.isSubstitution && record.readerRange.length > 0 {
                XCTAssertTrue(
                    destinationOnlyOffsets.contains(record.sourceRange.location),
                    "missing substituted marker for source offset \(record.sourceRange.location)"
                )
            }
        }
        for record in canvas.readerPresentation.offsetMap.records
        where !record.isSubstitution && record.role == .content {
            let intersection = NSIntersectionRange(record.sourceRange, plan.sourceRange)
            for offset in intersection.location..<NSMaxRange(intersection) {
                guard source.character(at: offset) != 0x0A else { continue }
                XCTAssertTrue(pairedOffsets.contains(offset), "missing content offset \(offset)")
            }
        }

        XCTAssertTrue(plan.renderables.contains { $0.fromBox != nil && $0.toBox == nil })
        XCTAssertTrue(plan.renderables.contains { $0.fromBox == nil && $0.toBox != nil })
    }

    func testLargeViewportUsesWordFallbackWithinLayerBudget() throws {
        let text = String(repeating: "word ", count: 1_200)
        let canvas = makeCanvas(text: text, size: NSSize(width: 50_000, height: 140))
        defer { canvas.window.orderOut(nil) }

        var measuredPlan: MorphPlan?
        let elapsed = ContinuousClock().measure {
            measuredPlan = try? MorphPlanner.build(
                from: canvas.editorEndpoint,
                to: canvas.readerEndpoint,
                sourceText: text,
                overlayView: canvas.overlay
            )
        }
        let plan = try XCTUnwrap(measuredPlan)

        XCTAssertGreaterThan(plan.pairedCharacterCount, MorphPlanner.pairedCharacterBudget)
        XCTAssertTrue(plan.usedWordFallback)
        XCTAssertLessThanOrEqual(plan.layerCount, MorphPlanner.layerBudget)
        XCTAssertTrue(plan.renderables.contains { $0.kind == .word })
        print("Mode morph 6,000-character layer count: \(plan.layerCount)")
        print("Mode morph 6,000-character planning time: \(elapsed)")
    }

    func testFourThousandCharacterPlanningTimeIsPrinted() throws {
        let text = String(repeating: "a", count: 4_000)
        let canvas = makeCanvas(text: text, size: NSSize(width: 40_000, height: 140))
        defer { canvas.window.orderOut(nil) }

        var measuredPlan: MorphPlan?
        let elapsed = ContinuousClock().measure {
            measuredPlan = try? MorphPlanner.build(
                from: canvas.editorEndpoint,
                to: canvas.readerEndpoint,
                sourceText: text,
                overlayView: canvas.overlay
            )
        }
        let plan = try XCTUnwrap(measuredPlan)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1e15

        XCTAssertGreaterThan(plan.pairedCharacterCount, 0)
        // Debug test build on a synthetic single 40,000 pt line; the release
        // build plans the same case several times faster.
        XCTAssertLessThan(milliseconds, 60, "planning took \(milliseconds) ms")
        print(
            "Mode morph 4,000-character case: \(milliseconds) ms, "
                + "paired=\(plan.pairedCharacterCount), layers=\(plan.layerCount)"
        )
    }

    func testReduceMotionAndEmptyDocumentProduceNoMorphRequest() {
        XCTAssertFalse(ModeMorphPolicy.canMorph(sourceLength: 0))
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertFalse(ModeMorphPolicy.canMorph(sourceLength: 1))
        }
    }

    private struct Surface {
        let window: NSWindow
        let scrollView: NSScrollView
        let textView: NSTextView
    }

    private struct Canvas {
        let window: NSWindow
        let editor: Surface
        let reader: Surface
        let overlay: NSView
        let readerPresentation: ReaderPresentation

        var editorEndpoint: MorphEndpoint {
            MorphEndpoint(
                kind: .editor,
                textView: editor.textView,
                scrollView: editor.scrollView
            )
        }

        var readerEndpoint: MorphEndpoint {
            MorphEndpoint(
                kind: .reader,
                textView: reader.textView,
                scrollView: reader.scrollView,
                offsetMap: readerPresentation.offsetMap
            )
        }
    }

    private func makeCanvas(text: String, size: NSSize) -> Canvas {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = root

        let editor = makeSurface(
            text: NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                    .foregroundColor: NSColor.textColor,
                    .ligature: 0,
                ]
            ),
            size: size,
            in: root,
            frame: NSRect(x: 0, y: 0, width: size.width, height: size.height / 2)
        )
        let presentation = ReaderPresentation.build(
            text: text,
            sourceMap: MarkdownSourceMap.parse(text)
        )
        let reader = makeSurface(
            text: presentation.attributedString,
            size: size,
            in: root,
            frame: NSRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2),
            usesReaderLayout: true
        )
        let overlay = NSView(frame: root.bounds)
        root.addSubview(overlay)
        root.layoutSubtreeIfNeeded()
        editor.textView.layoutSubtreeIfNeeded()
        reader.textView.layoutSubtreeIfNeeded()
        return Canvas(
            window: window,
            editor: editor,
            reader: reader,
            overlay: overlay,
            readerPresentation: presentation
        )
    }

    private func makeSurface(
        text: NSAttributedString,
        size: NSSize,
        in root: NSView? = nil,
        frame: NSRect? = nil,
        usesReaderLayout: Bool = false
    ) -> Surface {
        let window: NSWindow
        let host: NSView
        if let root {
            window = root.window!
            host = root
        } else {
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            host = NSView(frame: NSRect(origin: .zero, size: size))
            window.contentView = host
        }

        let scrollView = NSScrollView(
            frame: frame ?? NSRect(origin: .zero, size: size)
        )
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        let storage = NSTextStorage(attributedString: text)
        let layoutManager: NSLayoutManager = usesReaderLayout
            ? ReaderLayoutManager()
            : NSLayoutManager()
        if let readerLayoutManager = layoutManager as? ReaderLayoutManager {
            readerLayoutManager.theme = .default
        }
        let container = NSTextContainer(
            size: NSSize(width: scrollView.frame.width, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        let textView = NSTextView(
            frame: NSRect(origin: .zero, size: scrollView.frame.size),
            textContainer: container
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.frame.width,
            height: .greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        host.addSubview(scrollView)
        host.layoutSubtreeIfNeeded()
        var textFrame = textView.frame
        textFrame.size.height = max(textFrame.height, size.height)
        textView.frame = textFrame
        layoutManager.ensureLayout(for: container)
        return Surface(window: window, scrollView: scrollView, textView: textView)
    }
}

/// Drives the real container through a mode switch offscreen and checks that
/// the overlay actually animates instead of snapping to the end state.
final class ModeMorphContainerTests: XCTestCase {
    func testModeSwitchAnimatesGlyphLayersOverTime() throws {
        try XCTSkipIf(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "Reduce Motion disables the morph"
        )
        let text = (1...40).map {
            "# Heading \($0)\n\nSome **bold** and `code` paragraph text on line \($0).\n"
        }.joined()
        let document = Document(rawText: text)
        document.headings = MarkdownSourceMap.parse(text).headings

        let hosting = NSHostingView(rootView: EditorContainerView(
            document: document,
            configuration: .default,
            scrollToHeading: nil,
            isSelected: true
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.orderOut(nil) }
        // The window is never ordered front.
        func pump(seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                hosting.layoutSubtreeIfNeeded()
            }
        }
        func overlay(in view: NSView) -> ModeMorphOverlay? {
            if let overlay = view as? ModeMorphOverlay { return overlay }
            for subview in view.subviews {
                if let overlay = overlay(in: subview) { return overlay }
            }
            return nil
        }
        pump(seconds: 0.3)

        document.mode = .preview
        // The morph must be live in the same run-loop turn that first shows the
        // overlay (its layout pass), or the canvas flashes empty for a frame.
        var started: ModeMorphOverlay?
        for _ in 0..<50 where started == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            started = overlay(in: hosting)
        }
        let startedOverlay = try XCTUnwrap(started, "overlay should appear")
        XCTAssertTrue(startedOverlay.lastOutcome.hasPrefix("animating"), startedOverlay.lastOutcome)
        XCTAssertGreaterThan(startedOverlay.layer?.sublayers?.count ?? 0, 0)
        XCTAssertEqual(document.sharedEditorBridge.morphTextView()?.layer?.opacity, 0)

        pump(seconds: 0.08)
        let running = try XCTUnwrap(overlay(in: hosting), "overlay should still exist mid-morph")
        XCTAssertTrue(running.lastOutcome.hasPrefix("animating"), running.lastOutcome)
        let travelling = (running.layer?.sublayers ?? []).filter { layer in
            guard let presented = layer.presentation() else { return false }
            return abs(presented.position.x - layer.position.x) > 0.5
                || abs(presented.position.y - layer.position.y) > 0.5
        }
        XCTAssertFalse(
            travelling.isEmpty,
            "glyph layers should be between their start and end positions, not snapped to the end"
        )

        pump(seconds: 0.6)
        XCTAssertNil(overlay(in: hosting), "overlay should be removed after the morph finishes")
        XCTAssertEqual(document.sharedReaderBridge.morphTextView()?.layer?.opacity, 1)
        XCTAssertEqual(document.sharedEditorBridge.morphTextView()?.layer?.opacity, 0)

        // Resetting the surfaces redraws them at once, so the commit that drops
        // the glyph copies already shows the real glyphs.
        (document.sharedReaderBridge.morphTextView()?.layoutManager as? ReaderLayoutManager)?.morphGlyphOpacity = 0
        document.sharedReaderBridge.morphTextView()?.needsDisplay = true
        ModeMorphOverlay.resetSurfaceState(
            editorBridge: document.sharedEditorBridge,
            readerBridge: document.sharedReaderBridge,
            mode: .preview
        )
        XCTAssertEqual(document.sharedReaderBridge.morphTextView()?.needsDisplay, false)
        XCTAssertEqual(document.sharedEditorBridge.morphTextView()?.needsDisplay, false)
    }
}
