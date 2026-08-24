import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Markfops

final class UndoManagerTests: XCTestCase {
    func testTextViewUsesDocumentUndoManagerAndSupportsUndoRedo() {
        let document = Document(rawText: "Hello")
        let editor = makeEditor(for: document)
        replaceText(in: editor.textView, range: NSRange(location: 5, length: 0), with: "!")

        XCTAssertIdentical(editor.textView.undoManager, document.undoManager)
        XCTAssertTrue(document.undoManager.canUndo)
        document.undoManager.undo()
        XCTAssertEqual(editor.textView.string, "Hello")
        XCTAssertTrue(document.undoManager.canRedo)
        document.undoManager.redo()
        XCTAssertEqual(editor.textView.string, "Hello!")
    }

    func testUndoHistoriesAreIsolatedPerDocument() {
        let first = Document(rawText: "First")
        let second = Document(rawText: "Second")
        let firstEditor = makeEditor(for: first)
        let secondEditor = makeEditor(for: second)

        replaceText(in: firstEditor.textView, range: NSRange(location: 5, length: 0), with: "!")

        XCTAssertTrue(first.undoManager.canUndo)
        XCTAssertFalse(second.undoManager.canUndo)
        second.undoManager.undo()
        XCTAssertEqual(secondEditor.textView.string, "Second")
        XCTAssertEqual(firstEditor.textView.string, "First!")
    }

    func testUndoHistorySurvivesCoordinatorTeardownAndEditorRecreation() {
        let document = Document(rawText: "Hello")
        let original = makeEditor(for: document)
        replaceText(in: original.textView, range: NSRange(location: 5, length: 0), with: "!")
        original.coordinator.teardown()

        let recreated = makeEditor(for: document)
        XCTAssertTrue(document.undoManager.canUndo)
        document.undoManager.undo()
        XCTAssertEqual(document.rawText, "Hello")
        XCTAssertEqual(recreated.textView.string, "Hello")
        XCTAssertTrue(document.undoManager.canRedo)
        document.undoManager.redo()
        XCTAssertEqual(recreated.textView.string, "Hello!")
    }

    func testHostedDocumentSwitchRebuildsEditorAndPreservesEachHistory() {
        let first = Document(rawText: "First")
        let second = Document(rawText: "Second")
        let selection = HostedDocumentSelection(document: first)
        let hostingView = NSHostingView(rootView: HostedDocumentContent(selection: selection))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        settle(hostingView)
        guard let firstTextView = findTextView(in: hostingView) else {
            return XCTFail("The hosted editor did not create an NSTextView")
        }
        XCTAssertTrue(firstTextView.textStorage === first.textStorage)
        replaceText(in: firstTextView, range: NSRange(location: 5, length: 0), with: "!")

        selection.document = second
        settle(hostingView)
        guard let secondTextView = findTextView(in: hostingView) else {
            return XCTFail("The hosted editor did not recreate for the second document")
        }
        XCTAssertTrue(secondTextView.textStorage === second.textStorage)
        XCTAssertEqual(secondTextView.string, "Second")
        XCTAssertFalse(second.undoManager.canUndo)
        replaceText(in: secondTextView, range: NSRange(location: 6, length: 0), with: "!")

        selection.document = first
        settle(hostingView)
        guard let restoredFirstTextView = findTextView(in: hostingView) else {
            return XCTFail("The hosted editor did not recreate when switching back")
        }
        XCTAssertTrue(restoredFirstTextView.textStorage === first.textStorage)
        XCTAssertEqual(restoredFirstTextView.string, "First!")
        XCTAssertTrue(first.undoManager.canUndo)
        first.undoManager.undo()
        XCTAssertEqual(restoredFirstTextView.string, "First")
        XCTAssertEqual(second.rawText, "Second!")
        XCTAssertTrue(second.undoManager.canUndo)
    }

    func testHostedEditorHasInteractiveScrollableGeometry() {
        let text = Array(repeating: "A long line of editable Markdown text.", count: 200)
            .joined(separator: "\n")
        let document = Document(rawText: text)
        let selection = HostedDocumentSelection(document: document)
        let hostingView = NSHostingView(rootView: HostedDocumentContent(selection: selection))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.orderOut(nil) }

        settle(hostingView)
        guard let textView = findTextView(in: hostingView),
              let scrollView = textView.enclosingScrollView else {
            return XCTFail("The hosted editor did not create its scrollable text view")
        }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        settle(hostingView)

        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isVerticallyResizable)
        XCTAssertGreaterThan(textView.frame.height, scrollView.contentView.bounds.height)
        XCTAssertTrue(window.makeFirstResponder(textView))
        XCTAssertIdentical(window.firstResponder, textView)
    }

    func testHostedDocumentSwitchRestoresScrollPositionForEachDocument() {
        let first = Document(rawText: longDocument(prefix: "First"))
        let second = Document(rawText: longDocument(prefix: "Second"))
        let selection = HostedDocumentSelection(document: first)
        let hostingView = NSHostingView(rootView: HostedDocumentContent(selection: selection))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.orderOut(nil) }

        settle(hostingView)
        guard let firstTextView = findTextView(in: hostingView),
              let firstScrollView = firstTextView.enclosingScrollView else {
            return XCTFail("The first hosted editor did not create its scroll view")
        }
        firstTextView.layoutManager?.ensureLayout(for: firstTextView.textContainer!)
        settle(hostingView)

        let firstTargetY = (firstTextView.bounds.height - firstScrollView.contentView.bounds.height) * 0.55
        firstTextView.scroll(NSPoint(x: 0, y: firstTargetY))
        firstScrollView.reflectScrolledClipView(firstScrollView.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: firstScrollView
        )
        let savedRatio = first.scrollRatio
        XCTAssertGreaterThan(savedRatio, 0.4)

        selection.document = second
        settle(hostingView)
        selection.document = first
        settle(hostingView)

        guard let restoredTextView = findTextView(in: hostingView),
              let restoredScrollView = restoredTextView.enclosingScrollView else {
            return XCTFail("The restored editor did not create its scroll view")
        }
        let visibleRect = restoredScrollView.contentView.documentVisibleRect
        let restoredRatio = Double(
            (visibleRect.minY + visibleRect.height / 2) / restoredTextView.bounds.height
        )

        XCTAssertGreaterThan(visibleRect.minY, 0)
        XCTAssertEqual(restoredRatio, savedRatio, accuracy: 0.03)
    }

    func testWrappedEditorContentTracksHeadingAtViewportCenter() {
        let linesBeforeTarget = (0..<80).map { "Short line \($0)" }.joined(separator: "\n")
        let longWrappedLine = Array(repeating: "wrapped content", count: 2_000).joined(separator: " ")
        let text = "## First\n\(linesBeforeTarget)\n## Target\n\(longWrappedLine)"
        let document = Document(rawText: text)
        document.headings = HeadingParser.parseHeadings(in: text)
        guard let targetHeading = document.tocHeadings.last else {
            return XCTFail("The target heading was not parsed")
        }

        let selection = HostedDocumentSelection(document: document)
        let hostingView = NSHostingView(rootView: HostedDocumentContent(selection: selection))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.orderOut(nil) }

        settle(hostingView)
        guard let textView = findTextView(in: hostingView),
              let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return XCTFail("The hosted editor did not create its scrollable text view")
        }
        layoutManager.ensureLayout(for: textContainer)
        settle(hostingView)

        let targetCharacterRange = (text as NSString).range(of: "## Target")
        let targetGlyphRange = layoutManager.glyphRange(
            forCharacterRange: targetCharacterRange,
            actualCharacterRange: nil
        )
        let targetRect = layoutManager.boundingRect(forGlyphRange: targetGlyphRange, in: textContainer)
        let targetY = targetRect.minY + textView.textContainerOrigin.y
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )

        let ratioEstimatedLine = Int(
            (Double(max(document.lineCount - 1, 0)) * document.scrollRatio).rounded()
        )
        XCTAssertLessThan(ratioEstimatedLine, targetHeading.lineNumber)
        XCTAssertEqual(document.activeHeadingID, targetHeading.id)
    }

    func testManualSidebarScrollSuspendsAutomaticFollowingUntilResumed() {
        let context = SidebarScrollContext()
        context.lastTargetY = 120
        context.desiredTargetY = 180

        context.beginManualScrolling()

        XCTAssertNil(context.lastTargetY)
        XCTAssertNil(context.desiredTargetY)
        XCTAssertFalse(context.allowsAutomaticFollowing(force: false))
        XCTAssertTrue(context.allowsAutomaticFollowing(force: true))

        context.resumeAutomaticFollowing()

        XCTAssertTrue(context.allowsAutomaticFollowing(force: false))
    }

    private struct EditorFixture {
        let textView: MarkdownNSTextView
        let coordinator: TextViewCoordinator
    }

    private func makeEditor(for document: Document) -> EditorFixture {
        let textView = MarkdownNSTextView(textStorage: document.textStorage)
        let coordinator = TextViewCoordinator(document: document)
        textView.delegate = coordinator
        coordinator.textView = textView
        textView.allowsUndo = true
        if textView.string != document.rawText {
            textView.setPlainTextWithoutUndo(document.rawText)
        }
        return EditorFixture(textView: textView, coordinator: coordinator)
    }

    private func replaceText(in textView: MarkdownNSTextView, range: NSRange, with replacement: String) {
        XCTAssertTrue(textView.shouldChangeText(in: range, replacementString: replacement))
        textView.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
    }

    private func longDocument(prefix: String) -> String {
        (0..<300).map { "## \(prefix) section \($0)\nBody line \($0)" }
            .joined(separator: "\n")
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        view.layoutSubtreeIfNeeded()
    }

    private func findTextView(in view: NSView) -> MarkdownNSTextView? {
        if let textView = view as? MarkdownNSTextView { return textView }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) { return textView }
        }
        return nil
    }
}

@Observable
private final class HostedDocumentSelection {
    var document: Document

    init(document: Document) {
        self.document = document
    }
}

private struct HostedDocumentContent: View {
    @Bindable var selection: HostedDocumentSelection

    var body: some View {
        EditorContainerView(
            document: selection.document,
            configuration: .default,
            scrollToHeading: nil
        )
    }
}
