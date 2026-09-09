import AppKit
import SwiftUI
import XCTest
@testable import Markfops

/// Hosts the real container offscreen and switches modes to check that the
/// text cursor, its syntax reveal, and keyboard focus cross the switch.
/// The window is never ordered front and no input events are synthesized.
final class ModeSwitchCursorTests: XCTestCase {
    private struct Host {
        let document: Document
        let window: NSWindow
        let hosting: NSHostingView<EditorContainerView>
        let editor: MarkdownNSTextView
        let reader: ReaderNSTextView
        let coordinator: ReaderView.Coordinator

        func pump(seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                hosting.layoutSubtreeIfNeeded()
            }
        }

        func overlay(in view: NSView? = nil) -> ModeMorphOverlay? {
            let view = view ?? hosting
            if let overlay = view as? ModeMorphOverlay { return overlay }
            for subview in view.subviews {
                if let overlay = overlay(in: subview) { return overlay }
            }
            return nil
        }

        /// Switches mode and returns the overlay once it has planned, or nil
        /// when no overlay appeared (policy skipped the morph).
        func switchMode(to mode: EditMode) -> ModeMorphOverlay? {
            document.mode = mode
            var started: ModeMorphOverlay?
            for _ in 0..<50 where started == nil {
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                started = overlay()
            }
            return started
        }

        func waitForMorphToFinish() {
            let deadline = Date().addingTimeInterval(3)
            while overlay() != nil, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                hosting.layoutSubtreeIfNeeded()
            }
            // Focus is scheduled one run-loop turn after the switch.
            pump(seconds: 0.1)
        }

        func readerRange(of fragment: String) throws -> NSRange {
            let range = (reader.string as NSString).range(of: fragment)
            XCTAssertNotEqual(range.location, NSNotFound, "missing \(fragment) in reader")
            return range
        }
    }

    private var hosts: [Host] = []

    override func tearDown() {
        ModeMorphPolicy.isDisabledForTesting = false
        for host in hosts {
            host.window.orderOut(nil)
        }
        hosts.removeAll()
        super.tearDown()
    }

    private func makeHost(text: String, mode: EditMode) throws -> Host {
        let document = Document(rawText: text)
        document.headings = MarkdownSourceMap.parse(text).headings
        document.mode = mode

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
        // Never ordered front: the operator is using the machine.
        var editor: MarkdownNSTextView?
        var reader: ReaderNSTextView?
        for _ in 0..<100 where editor == nil || reader == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            hosting.layoutSubtreeIfNeeded()
            editor = document.sharedEditorBridge.morphTextView()
            reader = document.sharedReaderBridge.morphTextView()
            if mode == .preview, document.sharedReaderBridge.morphPresentation() == nil {
                reader = nil
            }
        }
        let coordinator = try XCTUnwrap(document.sharedReaderBridge.coordinator)
        coordinator.playsRefusalSound = false
        let host = Host(
            document: document,
            window: window,
            hosting: hosting,
            editor: try XCTUnwrap(editor, "editor should be mounted"),
            reader: try XCTUnwrap(reader, "reader should be mounted"),
            coordinator: coordinator
        )
        host.pump(seconds: 0.2)
        hosts.append(host)
        return host
    }

    private func assertPaired(
        _ plan: MorphPlan,
        sourceOffsets: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for offset in sourceOffsets {
            let renderable = plan.renderables.first { $0.sourceOffsets.contains(offset) }
            XCTAssertNotNil(renderable, "offset \(offset) missing from plan", file: file, line: line)
            XCTAssertNotNil(renderable?.fromBox, "offset \(offset) has no from box", file: file, line: line)
            XCTAssertNotNil(renderable?.toBox, "offset \(offset) has no to box", file: file, line: line)
        }
    }

    // MARK: - Editor to reader

    func testEditorCursorInsideBoldArrivesInTheReaderRevealedAndFocused() throws {
        let host = try makeHost(text: "Some **bold** text\n", mode: .edit)
        host.editor.setSelectedRange(NSRange(location: 9, length: 0))

        _ = host.switchMode(to: .preview)
        host.waitForMorphToFinish()

        XCTAssertEqual(host.reader.string, "Some **bold** text\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertTrue(host.window.firstResponder === host.reader, "reader should be first responder")

        host.reader.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(host.document.rawText, "Some **boXld** text\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
    }

    func testRevealedSyntaxPairsWithEditorSyntaxWhenMorphingToTheReader() throws {
        try XCTSkipIf(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "Reduce Motion disables the morph"
        )
        let text = "Intro line\n\nSome **bold** text\n"
        let host = try makeHost(text: text, mode: .edit)
        let bold = (text as NSString).range(of: "**bold**")
        host.editor.setSelectedRange(NSRange(location: bold.location + 4, length: 0))

        let overlay = try XCTUnwrap(host.switchMode(to: .preview), "overlay should appear")
        XCTAssertTrue(overlay.lastOutcome.hasPrefix("animating"), overlay.lastOutcome)
        let plan = try XCTUnwrap(overlay.lastPlan)
        // The reader was built with the reveal before planning, so every `*`
        // has a glyph on both surfaces and moves instead of fading.
        assertPaired(plan, sourceOffsets: [
            bold.location, bold.location + 1, NSMaxRange(bold) - 2, NSMaxRange(bold) - 1,
        ])
        XCTAssertTrue(host.reader.string.contains("**bold**"))
        host.waitForMorphToFinish()
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: bold.location + 4, length: 0))
    }

    // MARK: - Reader to editor

    func testReaderCaretArrivesInTheEditorAtTheSameSourceOffsetAndFocused() throws {
        let text = "Hello world\n\nSome **bold** text"
        let host = try makeHost(text: text, mode: .preview)
        XCTAssertEqual(host.reader.string, "Hello world\n\nSome bold text")
        host.reader.setSelectedRange(NSRange(location: 8, length: 0))

        _ = host.switchMode(to: .edit)
        host.waitForMorphToFinish()

        XCTAssertEqual(host.editor.selectedRange(), NSRange(location: 8, length: 0))
        XCTAssertTrue(host.window.firstResponder === host.editor, "editor should be first responder")
    }

    func testReaderCaretNextToHiddenSyntaxLandsOnTheSourceSideItSticksTo() throws {
        let text = "Some **bold** text"
        let host = try makeHost(text: text, mode: .preview)
        // Caret right after "bold" while the caret is not yet inside: the reveal
        // opens on selection, and the source cursor is before the closing `**`.
        let bold = try host.readerRange(of: "bold")
        host.reader.setSelectedRange(NSRange(location: NSMaxRange(bold), length: 0))
        XCTAssertEqual(host.reader.string, "Some **bold** text")

        _ = host.switchMode(to: .edit)
        host.waitForMorphToFinish()
        XCTAssertEqual(host.editor.selectedRange(), NSRange(location: 11, length: 0))
    }

    func testRevealedSyntaxPairsWithEditorSyntaxWhenMorphingToTheEditor() throws {
        try XCTSkipIf(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "Reduce Motion disables the morph"
        )
        let text = "Intro line\n\nSome **bold** text\n"
        let host = try makeHost(text: text, mode: .preview)
        let boldReader = try host.readerRange(of: "bold")
        host.reader.setSelectedRange(NSRange(location: boldReader.location + 2, length: 0))
        XCTAssertTrue(host.reader.string.contains("**bold**"))

        let overlay = try XCTUnwrap(host.switchMode(to: .edit), "overlay should appear")
        XCTAssertTrue(overlay.lastOutcome.hasPrefix("animating"), overlay.lastOutcome)
        let plan = try XCTUnwrap(overlay.lastPlan)
        let bold = (text as NSString).range(of: "**bold**")
        assertPaired(plan, sourceOffsets: [
            bold.location, bold.location + 1, NSMaxRange(bold) - 2, NSMaxRange(bold) - 1,
        ])
        host.waitForMorphToFinish()
        XCTAssertEqual(host.editor.selectedRange(), NSRange(location: bold.location + 4, length: 0))
    }

    // MARK: - Without a morph

    func testCursorCrossesASwitchThatDoesNotMorph() throws {
        ModeMorphPolicy.isDisabledForTesting = true
        let host = try makeHost(text: "Some **bold** text\n", mode: .edit)
        host.editor.setSelectedRange(NSRange(location: 9, length: 0))

        XCTAssertNil(host.switchMode(to: .preview), "policy should skip the morph")
        host.pump(seconds: 0.2)
        XCTAssertEqual(host.reader.string, "Some **bold** text\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertTrue(host.window.firstResponder === host.reader, "reader should be first responder")

        host.reader.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(host.reader.string, "Some bold text\n")
        host.reader.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertNil(host.switchMode(to: .edit), "policy should skip the morph")
        host.pump(seconds: 0.2)
        XCTAssertEqual(host.editor.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertTrue(host.window.firstResponder === host.editor, "editor should be first responder")
    }

    // MARK: - Command-B and Command-I

    func testBoldWrapsTheSelectionAndKeepsHiddenSyntaxInside() throws {
        let host = try makeHost(text: "Some **bold** text and more", mode: .preview)
        let selection = try host.readerRange(of: "e bold t")
        host.reader.setSelectedRange(selection)

        host.reader.wrapSelection(prefix: "**", suffix: "**")

        XCTAssertEqual(host.document.rawText, "Som**e **bold** t**ext and more")
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
        let presentation = try XCTUnwrap(host.document.sharedReaderBridge.morphPresentation())
        let selected = host.reader.selectedRange()
        XCTAssertGreaterThan(selected.length, 0)
        XCTAssertEqual(
            presentation.offsetMap.sourceRange(forReaderRange: selected),
            ("Som**e **bold** t**ext and more" as NSString).range(of: "e **bold** t")
        )
    }

    func testItalicWithACollapsedSelectionLeavesTheCaretBetweenTheDelimiters() throws {
        let host = try makeHost(text: "Hello world", mode: .preview)
        host.reader.setSelectedRange(NSRange(location: 5, length: 0))

        host.reader.wrapSelection(prefix: "*", suffix: "*")

        XCTAssertEqual(host.document.rawText, "Hello** world")
        XCTAssertEqual(host.reader.string, "Hello** world")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 6, length: 0))

        host.reader.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(host.document.rawText, "Hello*x* world")
        // The caret is inside the new emphasis, so its syntax stays revealed.
        XCTAssertEqual(host.reader.string, "Hello*x* world")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 7, length: 0))

        host.reader.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(host.reader.string, "Hellox world")
    }

    func testCommandBKeyEquivalentReachesTheWrap() throws {
        let host = try makeHost(text: "Hello world", mode: .preview)
        host.reader.setSelectedRange(try host.readerRange(of: "world"))
        // A constructed event handed to the view's own method; nothing is posted
        // to the system event queue.
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: host.window.windowNumber,
            context: nil,
            characters: "b",
            charactersIgnoringModifiers: "b",
            isARepeat: false,
            keyCode: 11
        ))
        XCTAssertTrue(host.reader.performKeyEquivalent(with: event))
        XCTAssertEqual(host.document.rawText, "Hello **world**")
        XCTAssertEqual(host.reader.string, "Hello **world**")
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "world"))
    }

    func testWrapOnAnUnroutableSelectionIsRefused() throws {
        let host = try makeHost(text: "- item\n- two", mode: .preview)
        host.reader.setSelectedRange(try host.readerRange(of: "• item"))
        host.reader.wrapSelection(prefix: "**", suffix: "**")
        XCTAssertEqual(host.document.rawText, "- item\n- two")
        XCTAssertEqual(host.coordinator.refusedEditCount, 1)
    }
}
