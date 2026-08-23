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
