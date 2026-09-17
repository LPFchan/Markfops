import AppKit
import SwiftUI
import XCTest
@testable import Markfops

final class ReaderRevealTests: XCTestCase {
    func testInlineConstructRevealsWhenCursorIsInsideOrAtEitherEdge() {
        let text = "A **bold** word"
        let map = MarkdownSourceMap.parse(text)
        let bold = (text as NSString).range(of: "**bold**")

        XCTAssertEqual(ReaderReveal.range(in: map, sourceCursor: bold.location + 4), bold)
        XCTAssertEqual(ReaderReveal.range(in: map, sourceCursor: bold.location), bold)
        XCTAssertEqual(ReaderReveal.range(in: map, sourceCursor: NSMaxRange(bold)), bold)
        XCTAssertNil(ReaderReveal.range(in: map, sourceCursor: 0))
        XCTAssertNil(ReaderReveal.range(in: map, sourceCursor: (text as NSString).length))
    }

    func testHeadingRevealsWholeLineAndNestedInlineRevealsOutermost() {
        let heading = "# Head *em*\nbody"
        let headingMap = MarkdownSourceMap.parse(heading)
        let headingRange = (heading as NSString).range(of: "# Head *em*")
        XCTAssertEqual(ReaderReveal.range(in: headingMap, sourceCursor: 3), headingRange)
        XCTAssertEqual(ReaderReveal.range(in: headingMap, sourceCursor: 9), headingRange)
        XCTAssertNil(ReaderReveal.range(in: headingMap, sourceCursor: (heading as NSString).length))

        let nested = "*a **b** c*"
        let nestedMap = MarkdownSourceMap.parse(nested)
        XCTAssertEqual(
            ReaderReveal.range(in: nestedMap, sourceCursor: 5),
            NSRange(location: 0, length: (nested as NSString).length)
        )

        let code = "x `code` y"
        let codeMap = MarkdownSourceMap.parse(code)
        XCTAssertEqual(
            ReaderReveal.range(in: codeMap, sourceCursor: 4),
            (code as NSString).range(of: "`code`")
        )

        let list = "- item"
        XCTAssertEqual(
            ReaderReveal.range(in: MarkdownSourceMap.parse(list), sourceCursor: 3),
            NSRange(location: 0, length: 2),
            "the item's marker reveals while the cursor is in the item"
        )
    }

    func testOnlyTheInnermostListItemRevealsItsMarker() {
        let text = "- a\n  - b\n- c"
        let source = text as NSString
        let map = MarkdownSourceMap.parse(text)
        XCTAssertEqual(ReaderReveal.range(in: map, sourceCursor: 2), NSRange(location: 0, length: 2))
        XCTAssertEqual(
            ReaderReveal.range(in: map, sourceCursor: source.range(of: "b").location),
            source.range(of: "- ", options: [], range: NSRange(location: 4, length: 5)),
            "the nested item's marker, not the parent's"
        )
        XCTAssertEqual(
            ReaderReveal.range(in: map, sourceCursor: source.range(of: "c").location),
            NSRange(location: source.range(of: "- c").location, length: 2)
        )
        let ordered = "1. one\n2. two"
        XCTAssertEqual(ReaderReveal.range(in: MarkdownSourceMap.parse(ordered), sourceCursor: 9), NSRange(location: 7, length: 3))
        let task = "- [ ] do"
        XCTAssertEqual(ReaderReveal.range(in: MarkdownSourceMap.parse(task), sourceCursor: 7), NSRange(location: 0, length: 6))
    }

    func testFencedCodeBlockRevealsBothFencesAndQuoteRevealsItsMarkers() {
        let text = "Intro\n\n```swift\nlet x = 1\n```\n\nAfter **b**\n"
        let source = text as NSString
        let map = MarkdownSourceMap.parse(text)
        let closingFence = source.range(of: "```", options: .backwards)
        let block = NSRange(
            location: source.range(of: "```swift").location,
            length: NSMaxRange(closingFence) - source.range(of: "```swift").location
        )
        XCTAssertEqual(block, source.range(of: "```swift\nlet x = 1\n```"))
        XCTAssertEqual(ReaderReveal.range(in: map, sourceCursor: source.range(of: "x = 1").location), block)
        XCTAssertEqual(ReaderReveal.range(in: map, sourceCursor: source.range(of: "```swift").location + 3), block, "on the opening fence")
        XCTAssertEqual(ReaderReveal.range(in: map, sourceCursor: closingFence.location + 1), block, "on the closing fence")
        XCTAssertEqual(ReaderReveal.range(in: map, sourceCursor: NSMaxRange(block)), block, "at the end of the closing fence")
        XCTAssertNil(ReaderReveal.range(in: map, sourceCursor: NSMaxRange(block) + 1), "on the empty line after the block")
        XCTAssertNil(ReaderReveal.range(in: map, sourceCursor: source.range(of: "After").location))
        XCTAssertNil(ReaderReveal.range(in: map, sourceCursor: 2))

        let indented = "para\n\n    code\n"
        XCTAssertNil(ReaderReveal.range(in: MarkdownSourceMap.parse(indented), sourceCursor: 10))

        let quote = "> one\n> two *em*\n\npara"
        let quoteSource = quote as NSString
        let quoteMap = MarkdownSourceMap.parse(quote)
        let quoteRange = quoteSource.range(of: "> one\n> two *em*")
        XCTAssertEqual(ReaderReveal.range(in: quoteMap, sourceCursor: 3), quoteRange)
        XCTAssertEqual(ReaderReveal.range(in: quoteMap, sourceCursor: quoteSource.range(of: "em").location), quoteRange, "an inline inside the quote reveals with it")
        XCTAssertNil(ReaderReveal.range(in: quoteMap, sourceCursor: quoteSource.range(of: "para").location))

        let nested = "> outer\n> > inner\n"
        let nestedMap = MarkdownSourceMap.parse(nested)
        XCTAssertEqual(
            ReaderReveal.range(in: nestedMap, sourceCursor: (nested as NSString).range(of: "inner").location),
            (nested as NSString).range(of: "> outer\n> > inner")
        )
    }
}

final class ReaderNewlineTests: XCTestCase {
    private func edit(_ text: String, at offset: Int, length: Int = 0) -> MarkdownSourceEdit {
        ReaderNewline.edit(
            in: text as NSString,
            sourceMap: MarkdownSourceMap.parse(text),
            selection: NSRange(location: offset, length: length)
        )
    }

    /// The source after Enter and where the caret lands in it.
    private func after(_ text: String, at offset: Int, length: Int = 0) -> (text: String, caret: Int) {
        let edit = edit(text, at: offset, length: length)
        XCTAssertEqual(edit.kept, [])
        XCTAssertEqual(edit.selection.length, 0)
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection.location)
    }

    private func assertAfter(
        _ text: String, at offset: Int, length: Int = 0,
        is expected: String, caret: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let result = after(text, at: offset, length: length)
        XCTAssertEqual(result.text, expected, file: file, line: line)
        XCTAssertEqual(result.caret, caret, file: file, line: line)
    }

    func testProseGetsAParagraphBreakAndRawBlocksKeepASingleNewline() {
        XCTAssertEqual(edit("Hello world", at: 5), MarkdownSourceEdit(
            range: NSRange(location: 5, length: 0), replacement: "\n\n",
            selection: NSRange(location: 7, length: 0), kept: []
        ))
        XCTAssertEqual(edit("Hello world", at: 11).replacement, "\n\n")
        XCTAssertEqual(edit("# Title", at: 7).replacement, "\n\n")
        XCTAssertEqual(edit("", at: 0).replacement, "\n\n")
        XCTAssertEqual(edit("para\n\nnext", at: 5).replacement, "\n\n")
        XCTAssertEqual(edit("---", at: 3).replacement, "\n\n")
        XCTAssertEqual(edit("```\ncode\n```", at: 6).replacement, "\n")
        XCTAssertEqual(edit("    indented", at: 8).replacement, "\n")
        XCTAssertEqual(edit("| a |\n|---|\n| 1 |", at: 2).replacement, "\n")
        XCTAssertEqual(edit("<div>\nx\n</div>", at: 7).replacement, "\n")
        XCTAssertEqual(edit("---\ntitle: x\n---\nbody", at: 6).replacement, "\n")
        XCTAssertEqual(edit("---\ntitle: x\n---\nbody", at: 20).replacement, "\n\n")
        // A code block inside an item is still code.
        XCTAssertEqual(edit("- item\n\n  ```\n  code\n  ```", at: 16).replacement, "\n")
        // A selection is replaced by the break.
        assertAfter("Hello world", at: 5, length: 3, is: "Hello\n\nrld", caret: 7)
    }

    func testEnterContinuesAListWithTheSameMarker() {
        assertAfter("- item", at: 6, is: "- item\n- ", caret: 9)
        assertAfter("* item", at: 6, is: "* item\n* ", caret: 9)
        assertAfter("+ item", at: 6, is: "+ item\n+ ", caret: 9)
        assertAfter("- one\n- two", at: 11, is: "- one\n- two\n- ", caret: 14)
        // In the middle of the item the text after the caret becomes the new item.
        assertAfter("- item", at: 4, is: "- it\n- em", caret: 7)
        // A selection is replaced.
        assertAfter("- item", at: 3, length: 2, is: "- i\n- m", caret: 6)
        // A later paragraph of the item still continues the item.
        assertAfter("- item\n\n  second", at: 16, is: "- item\n\n  second\n- ", caret: 19)
    }

    func testEnterNumbersOrderedItemsAndKeepsTheirDelimiter() {
        assertAfter("1. one", at: 6, is: "1. one\n2. ", caret: 10)
        assertAfter("3. three", at: 8, is: "3. three\n4. ", caret: 12)
        assertAfter("3) three", at: 8, is: "3) three\n4) ", caret: 12)
        assertAfter("9. nine", at: 7, is: "9. nine\n10. ", caret: 12)
        XCTAssertEqual(ReaderNewline.nextMarker(after: "12) "), "13) ")
        XCTAssertEqual(ReaderNewline.nextMarker(after: "-   "), "- ")
    }

    func testEnterContinuesATaskItemWithAnUncheckedBox() {
        assertAfter("- [ ] task", at: 10, is: "- [ ] task\n- [ ] ", caret: 17)
        assertAfter("- [x] done", at: 10, is: "- [x] done\n- [ ] ", caret: 17)
        assertAfter("1. [x] done", at: 11, is: "1. [x] done\n2. [ ] ", caret: 19)
    }

    func testEnterKeepsTheIndentOfANestedItemAndTheQuoteAroundAList() {
        assertAfter("- a\n  - b", at: 9, is: "- a\n  - b\n  - ", caret: 14)
        assertAfter("1. a\n   - b", at: 11, is: "1. a\n   - b\n   - ", caret: 17)
        assertAfter("> - item", at: 8, is: "> - item\n> - ", caret: 13)
        assertAfter("- > quoted", at: 10, is: "- > quoted\n  > ", caret: 15)
    }

    func testEnterWithTheCaretBeforeAnItemsContentStartsAnItemAbove() {
        assertAfter("- a\n- b", at: 4, is: "- a\n- \n- b", caret: 9)
        assertAfter("- item", at: 0, is: "- \n- item", caret: 5)
    }

    func testEnterOnAnEmptyItemRemovesItsMarkerAndEndsTheList() {
        assertAfter("- item\n- ", at: 9, is: "- item\n", caret: 7)
        assertAfter("- ", at: 2, is: "", caret: 0)
        assertAfter("1. one\n2. ", at: 10, is: "1. one\n", caret: 7)
        assertAfter("- [ ] task\n- [ ] ", at: 17, is: "- [ ] task\n", caret: 11)
        // Inside a quote the quote stays.
        assertAfter("> - a\n> - ", at: 10, is: "> - a\n> ", caret: 8)
        // A nested empty item outdents one level. (A lone `- ` right under
        // an item's text is a setext underline, not a nested item, so the
        // nested list needs an item of its own first.)
        assertAfter("- a\n  - b\n  - ", at: 14, is: "- a\n  - b\n- ", caret: 12)
        assertAfter("1. a\n   - b\n   - ", at: 17, is: "1. a\n   - b\n- ", caret: 14)
        assertAfter("> - a\n>   - b\n>   - ", at: 20, is: "> - a\n>   - b\n> - ", caret: 18)
    }

    func testEnterContinuesAQuoteAndRemovesTheMarkersOfAnEmptyQuoteLine() {
        assertAfter("> quote", at: 7, is: "> quote\n> ", caret: 10)
        assertAfter("> quote", at: 4, is: "> qu\n> ote", caret: 7)
        assertAfter("> > deep", at: 8, is: "> > deep\n> > ", caret: 13)
        // A lazy continuation line continues the quote's markers.
        assertAfter("> a\nb", at: 5, is: "> a\nb\n> ", caret: 8)
        // The caret inside the markers acts at the content start.
        assertAfter("> quote", at: 0, is: "> \n> quote", caret: 5)
        // Only markers: remove them.
        assertAfter("> a\n> ", at: 6, is: "> a\n", caret: 4)
        assertAfter("> ", at: 2, is: "", caret: 0)
        assertAfter("> > a\n> > ", at: 10, is: "> > a\n", caret: 6)
        assertAfter("- > a\n  > ", at: 10, is: "- > a\n  ", caret: 8)
    }

    func testAnEnterThatWritesOrRemovesAMarkerChangesTheBlock() {
        XCTAssertFalse(ReaderNewline.changesBlock(edit("Hello world", at: 5)))
        XCTAssertFalse(ReaderNewline.changesBlock(edit("Hello world", at: 2, length: 3)))
        XCTAssertFalse(ReaderNewline.changesBlock(edit("```\ncode\n```", at: 6)))
        XCTAssertTrue(ReaderNewline.changesBlock(edit("- item", at: 6)))
        XCTAssertTrue(ReaderNewline.changesBlock(edit("> quote", at: 7)))
        XCTAssertTrue(ReaderNewline.changesBlock(edit("- item\n- ", at: 9)))
        XCTAssertTrue(ReaderNewline.changesBlock(edit("- a\n  - b\n  - ", at: 14)))
        XCTAssertTrue(ReaderNewline.changesBlock(edit("> a\n> ", at: 6)))
    }
}

