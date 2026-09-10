import AppKit
import XCTest
@testable import Markfops

final class MarkdownHeadingEditTests: XCTestCase {
    private func edit(_ text: String, at location: Int, length: Int = 0, level: Int) -> MarkdownSourceEdit? {
        MarkdownHeadingEdit.edit(in: text as NSString, selection: NSRange(location: location, length: length), level: level)
    }

    private func applied(_ text: String, _ edit: MarkdownSourceEdit) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testParagraphBecomesHeadingOneWithTheContentShifted() throws {
        let text = "Hello world\n\nNext"
        let result = try XCTUnwrap(edit(text, at: 3, level: 1))
        XCTAssertEqual(result.range, NSRange(location: 0, length: 11))
        XCTAssertEqual(result.replacement, "# Hello world")
        XCTAssertEqual(applied(text, result), "# Hello world\n\nNext")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 11), "the content is selected, not the prefix")
        XCTAssertEqual(result.kept, [.init(old: NSRange(location: 0, length: 11), newLocation: 2)])
        XCTAssertEqual(result.newOffset(forOldOffset: 0), 2)
        XCTAssertEqual(result.newOffset(forOldOffset: 10), 12)
        XCTAssertEqual(result.newOffset(forOldOffset: 11), 13, "the newline after the line shifts")
        XCTAssertEqual(result.newOffset(forOldOffset: 13), 15)
    }

    func testHeadingOneBecomesHeadingTwoKeepingTheFirstHashAndTheSpace() throws {
        let text = "# Title\nbody"
        let result = try XCTUnwrap(edit(text, at: 3, level: 2))
        XCTAssertEqual(result.replacement, "## Title")
        XCTAssertEqual(applied(text, result), "## Title\nbody")
        XCTAssertEqual(result.selection, NSRange(location: 3, length: 5))
        XCTAssertEqual(result.newOffset(forOldOffset: 0), 0, "the old hash is the first new hash")
        XCTAssertEqual(result.newOffset(forOldOffset: 1), 2, "the space follows the new hashes")
        XCTAssertEqual(result.newOffset(forOldOffset: 2), 3)
        XCTAssertEqual(result.newOffset(forOldOffset: 6), 7)
        XCTAssertEqual(result.newOffset(forOldOffset: 7), 8)
        let survivors = (0..<12).compactMap { result.newOffset(forOldOffset: $0) }
        XCTAssertEqual(Set(survivors).count, survivors.count, "no two characters land on one offset")
    }

    func testHeadingTwoBecomesAParagraphDroppingThePrefix() throws {
        let text = "## Title"
        let result = try XCTUnwrap(edit(text, at: 4, level: 0))
        XCTAssertEqual(result.replacement, "Title")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 5))
        XCTAssertEqual([0, 1, 2].map { result.newOffset(forOldOffset: $0) }, [nil, nil, nil])
        XCTAssertEqual(result.newOffset(forOldOffset: 3), 0)
        XCTAssertEqual(result.newOffset(forOldOffset: 7), 4)
        XCTAssertEqual(result.newOffset(forOldOffset: 8), 5)
    }

    func testHeadingThreeBecomesHeadingOneDroppingTheExtraHashes() throws {
        let text = "###  Title"
        let result = try XCTUnwrap(edit(text, at: 6, level: 1))
        XCTAssertEqual(result.replacement, "# Title")
        XCTAssertEqual(result.newOffset(forOldOffset: 0), 0)
        XCTAssertNil(result.newOffset(forOldOffset: 1))
        XCTAssertNil(result.newOffset(forOldOffset: 2))
        XCTAssertEqual(result.newOffset(forOldOffset: 3), 1, "the first space is kept")
        XCTAssertNil(result.newOffset(forOldOffset: 4), "the second space goes")
        XCTAssertEqual(result.newOffset(forOldOffset: 5), 2)
    }

    func testAMultiLineSelectionRewritesEveryNonBlankLine() throws {
        let text = "a\n\nb\nc"
        let result = try XCTUnwrap(edit(text, at: 0, length: 4, level: 1))
        XCTAssertEqual(result.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(result.replacement, "# a\n\n# b")
        XCTAssertEqual(applied(text, result), "# a\n\n# b\nc")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 6))
        XCTAssertEqual(result.newOffset(forOldOffset: 0), 2)
        XCTAssertEqual(result.newOffset(forOldOffset: 1), 3)
        XCTAssertEqual(result.newOffset(forOldOffset: 2), 4)
        XCTAssertEqual(result.newOffset(forOldOffset: 3), 7)
        XCTAssertEqual(result.newOffset(forOldOffset: 5), 9)
    }

    func testLeadingSpacesStayInFrontOfANewPrefixAndGoWithAnOldOne() throws {
        let text = "   text"
        let result = try XCTUnwrap(edit(text, at: 5, level: 1))
        XCTAssertEqual(result.replacement, "   # text")
        XCTAssertEqual(result.selection, NSRange(location: 5, length: 4))
        XCTAssertEqual(result.newOffset(forOldOffset: 1), 1)
        XCTAssertEqual(result.newOffset(forOldOffset: 3), 5)

        let heading = "   # text"
        let plain = try XCTUnwrap(edit(heading, at: 6, level: 0))
        XCTAssertEqual(plain.replacement, "text")
        XCTAssertEqual(plain.selection, NSRange(location: 0, length: 4))
        XCTAssertNil(plain.newOffset(forOldOffset: 0))
        XCTAssertEqual(plain.newOffset(forOldOffset: 5), 0)
    }

    func testSetextHeadingsBlankLinesAndBadLevelsAreRefused() {
        XCTAssertNil(edit("Title\n=====\nbody", at: 2, level: 1), "a setext heading is not converted")
        XCTAssertNil(edit("Title\n-----", at: 8, level: 1), "nor its underline")
        XCTAssertNotNil(edit("para\n\n---", at: 8, level: 1), "a thematic break after a blank line is a plain line")
        XCTAssertNil(edit("\n\n", at: 1, level: 1))
        XCTAssertNil(edit("", at: 0, level: 1))
        XCTAssertNil(edit("text", at: 0, level: 7))
        XCTAssertNil(edit("text", at: 0, level: -1))
    }

    func testAnUnchangedLineStillReportsItsContentSelection() throws {
        let text = "# Title"
        let result = try XCTUnwrap(edit(text, at: 0, level: 1))
        XCTAssertEqual(result.replacement, "# Title")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 5))
    }

    func testEditorCommandRewritesOnlyTheLineAndUndoesInOneStep() {
        let document = Document(rawText: "Intro\n\nHello world\n\nOutro")
        let textView = MarkdownNSTextView(textStorage: document.textStorage)
        let coordinator = TextViewCoordinator(document: document)
        textView.delegate = coordinator
        coordinator.textView = textView
        textView.allowsUndo = true
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        // In the app each command arrives in its own event and gets its own
        // undo group; the test opens the groups itself.
        let undoManager = document.undoManager
        XCTAssertIdentical(textView.undoManager, undoManager)
        undoManager.groupsByEvent = false
        func command(_ level: Int) {
            undoManager.beginUndoGrouping()
            textView.applyHeading(level: level)
            textView.breakUndoCoalescing()
            undoManager.endUndoGrouping()
        }

        command(1)
        XCTAssertEqual(textView.string, "Intro\n\n# Hello world\n\nOutro")
        XCTAssertEqual(document.rawText, "Intro\n\n# Hello world\n\nOutro")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 11))
        command(2)
        XCTAssertEqual(textView.string, "Intro\n\n## Hello world\n\nOutro")
        command(0)
        XCTAssertEqual(textView.string, "Intro\n\nHello world\n\nOutro")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 11))

        undoManager.undo()
        XCTAssertEqual(textView.string, "Intro\n\n## Hello world\n\nOutro", "one step restores the previous line")
        undoManager.undo()
        XCTAssertEqual(textView.string, "Intro\n\n# Hello world\n\nOutro")
        undoManager.undo()
        XCTAssertEqual(textView.string, "Intro\n\nHello world\n\nOutro")
    }
}

final class MarkdownBlockPrefixTests: XCTestCase {
    private func changes(_ text: String, _ location: Int, _ length: Int = 0, typing replacement: String) -> Bool {
        MarkdownBlockPrefix.changes(
            in: text as NSString,
            replacing: NSRange(location: location, length: length),
            with: replacement
        )
    }

    func testPrefixRunsCoverQuoteHeadingAndListMarkers() {
        func run(_ line: String) -> String {
            (line as NSString).substring(with: MarkdownBlockPrefix.range(inLine: line as NSString))
        }
        XCTAssertEqual(run("Hello"), "")
        XCTAssertEqual(run("#Hello"), "#")
        XCTAssertEqual(run("# Hello"), "# ")
        XCTAssertEqual(run("  > ## Quote"), "  > ## ")
        XCTAssertEqual(run("- item"), "- ")
        XCTAssertEqual(run("-item"), "")
        XCTAssertEqual(run("1. item"), "1. ")
        XCTAssertEqual(run("1.item"), "")
        XCTAssertEqual(run("* "), "* ")
    }

    func testKeystrokesThatChangeTheBlockAnimateAndOthersDoNot() {
        XCTAssertTrue(changes("Hello", 0, typing: "#"), "a hash at the start starts a prefix")
        XCTAssertTrue(changes("#Hello", 1, typing: " "), "the space makes it a heading")
        XCTAssertTrue(changes("# Hello", 1, typing: "#"), "a second hash changes the level")
        XCTAssertTrue(changes("# Hello", 1, 1, typing: ""), "removing the space breaks the heading")
        XCTAssertTrue(changes("-Hello", 1, typing: " "), "the space completes a bullet")
        XCTAssertTrue(changes("1.Hello", 2, typing: " "), "the space completes an ordered marker")
        XCTAssertTrue(changes("Hello", 0, typing: "> "), "a pasted quote mark counts")

        XCTAssertFalse(changes("Hello", 2, typing: "x"), "typing inside a word")
        XCTAssertFalse(changes("# Hello", 2, typing: "H"), "typing at the start of a heading's content")
        XCTAssertFalse(changes("- item", 2, typing: "x"), "typing at the start of a list item's content")
        XCTAssertFalse(changes("Hello", 0, typing: "-"), "a dash alone is still a paragraph")
        XCTAssertFalse(changes("Hello\nworld", 5, 1, typing: ""), "joining two lines is left instant")
        XCTAssertFalse(changes("Hello", 0, typing: "\n"), "a line break is left instant")
        XCTAssertFalse(changes("Hello", 0, 2, typing: "He"), "a replacement with the same text")
    }

    func testRawBlocksAreDetected() {
        let text = "para\n\n```\n# not a heading\n```\n\n# heading"
        let map = MarkdownSourceMap.parse(text)
        let inCode = (text as NSString).range(of: "# not").location
        let inHeading = (text as NSString).range(of: "# heading").location
        XCTAssertTrue(MarkdownBlockPrefix.isInsideRawBlock(map, offset: inCode))
        XCTAssertFalse(MarkdownBlockPrefix.isInsideRawBlock(map, offset: inHeading))
        XCTAssertFalse(MarkdownBlockPrefix.isInsideRawBlock(map, offset: 0))
    }
}
