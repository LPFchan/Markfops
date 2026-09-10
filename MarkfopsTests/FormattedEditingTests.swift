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

final class ReaderOffsetMapEditingTests: XCTestCase {
    private func presentation(_ text: String, reveal: NSRange? = nil) -> ReaderPresentation {
        ReaderPresentation.build(
            text: text,
            sourceMap: MarkdownSourceMap.parse(text),
            revealedSourceRange: reveal
        )
    }

    private func readerRange(of fragment: String, in presentation: ReaderPresentation) -> NSRange {
        let range = (presentation.attributedString.string as NSString).range(of: fragment)
        XCTAssertNotEqual(range.location, NSNotFound, "missing \(fragment)")
        return range
    }

    func testSourceRangeMapsCharactersAndIncludesHiddenSyntaxStrictlyInside() throws {
        let text = "Some **bold** and `code` [link](https://x.y) here\n- item\n\nsee ![alt](missing.png)"
        let built = presentation(text)
        let source = text as NSString
        let map = built.offsetMap
        XCTAssertEqual(
            built.attributedString.string,
            "Some bold and code link here\n• item\n\nsee alt"
        )

        XCTAssertEqual(
            map.sourceRange(forReaderRange: readerRange(of: "bold", in: built)),
            source.range(of: "bold")
        )
        XCTAssertEqual(
            map.sourceRange(forReaderRange: readerRange(of: " bold ", in: built)),
            source.range(of: " **bold** ")
        )
        XCTAssertEqual(
            map.sourceRange(forReaderRange: readerRange(of: "code link", in: built)),
            source.range(of: "code` [link")
        )
        XCTAssertEqual(
            map.sourceRange(forReaderRange: readerRange(of: "alt", in: built)),
            source.range(of: "alt")
        )
        XCTAssertNil(map.sourceRange(forReaderRange: readerRange(of: "• item", in: built)))
        XCTAssertNil(map.sourceRange(forReaderRange: readerRange(of: "\n• ", in: built)))
        XCTAssertNil(map.sourceRange(forReaderRange: NSRange(location: 0, length: 10_000)))
    }

    func testDeletionRangeTakesASubstitutedGlyphsWholeSource() {
        let text = "Some **bold** here\n- item\n- [x] done\n\n---\n\n1. one\nafter"
        let built = presentation(text)
        let source = text as NSString
        let map = built.offsetMap
        XCTAssertEqual(
            built.attributedString.string,
            "Some bold here\n• item\n☑ done\n\n\u{200B}\n\n1. one\nafter"
        )

        // One-to-one text deletes as it does through the plain mapping.
        XCTAssertEqual(map.sourceRange(forDeletionOf: readerRange(of: "bold", in: built)), source.range(of: "bold"))
        XCTAssertEqual(map.sourceRange(forDeletionOf: readerRange(of: " bold ", in: built)), source.range(of: " **bold** "))

        // Any character of a marker deletes the whole marker run.
        let bullet = readerRange(of: "• ", in: built)
        let dash = NSRange(location: source.range(of: "- item").location, length: 2)
        XCTAssertEqual(map.sourceRange(forDeletionOf: bullet), dash)
        XCTAssertEqual(map.sourceRange(forDeletionOf: NSRange(location: bullet.location + 1, length: 1)), dash)
        XCTAssertEqual(map.sourceRange(forDeletionOf: readerRange(of: "• item", in: built)), source.range(of: "- item"))
        XCTAssertEqual(map.sourceRange(forDeletionOf: readerRange(of: "\n• ", in: built)), source.range(of: "\n- "))
        XCTAssertEqual(map.sourceRange(forDeletionOf: readerRange(of: "☑ ", in: built)), source.range(of: "- [x] "))
        let number = readerRange(of: "1. ", in: built)
        XCTAssertEqual(
            map.sourceRange(forDeletionOf: NSRange(location: NSMaxRange(number) - 1, length: 1)),
            source.range(of: "1. ")
        )

        // A thematic break is one glyph standing for its whole line.
        XCTAssertEqual(map.sourceRange(forDeletionOf: readerRange(of: "\u{200B}", in: built)), source.range(of: "---"))
        XCTAssertEqual(map.sourceRange(forDeletionOf: readerRange(of: "\u{200B}\n", in: built)), source.range(of: "---\n"))

        XCTAssertNil(map.sourceRange(forDeletionOf: NSRange(location: 3, length: 0)))
        XCTAssertNil(map.sourceRange(forDeletionOf: NSRange(location: 0, length: 10_000)))

        let frontMatter = "---\ntitle: x\n---\nbody"
        let withFrontMatter = presentation(frontMatter)
        XCTAssertEqual(
            withFrontMatter.offsetMap.sourceRange(forDeletionOf: readerRange(of: "title", in: withFrontMatter)),
            (frontMatter as NSString).range(of: "---\ntitle: x\n---")
        )
    }

    func testInsertionOffsetSticksToContentNextToHiddenSyntax() {
        let text = "Some **bold** text"
        let built = presentation(text)
        let bold = readerRange(of: "bold", in: built)
        XCTAssertEqual(built.offsetMap.sourceInsertionOffset(forReaderOffset: bold.location), 7)
        XCTAssertEqual(built.offsetMap.sourceInsertionOffset(forReaderOffset: NSMaxRange(bold)), 11)
        XCTAssertEqual(built.offsetMap.sourceInsertionOffset(forReaderOffset: 2), 2)
        XCTAssertEqual(
            built.offsetMap.sourceRange(forReaderRange: NSRange(location: NSMaxRange(bold), length: 0)),
            NSRange(location: 11, length: 0)
        )

        let adjacent = presentation("**a**_b_")
        XCTAssertEqual(adjacent.attributedString.string, "ab")
        XCTAssertEqual(adjacent.offsetMap.sourceInsertionOffset(forReaderOffset: 0), 2)
        XCTAssertEqual(adjacent.offsetMap.sourceInsertionOffset(forReaderOffset: 1), 3)
        XCTAssertEqual(adjacent.offsetMap.sourceInsertionOffset(forReaderOffset: 2), 7)

        let code = presentation("x `code` y")
        let codeRange = readerRange(of: "code", in: code)
        XCTAssertEqual(code.offsetMap.sourceInsertionOffset(forReaderOffset: codeRange.location), 3)
        XCTAssertEqual(code.offsetMap.sourceInsertionOffset(forReaderOffset: NSMaxRange(codeRange)), 7)
    }

    func testInsertionOffsetLandsAfterBlockPrefixesAndListMarkers() {
        let heading = presentation("# Title\nbody")
        XCTAssertEqual(heading.offsetMap.sourceInsertionOffset(forReaderOffset: 0), 2)

        let quote = presentation("para\n> quote")
        let quoteRange = readerRange(of: "quote", in: quote)
        XCTAssertEqual(quote.offsetMap.sourceInsertionOffset(forReaderOffset: quoteRange.location), 7)

        let list = presentation("- item")
        let item = readerRange(of: "item", in: list)
        XCTAssertEqual(list.offsetMap.sourceInsertionOffset(forReaderOffset: item.location), 2)
        XCTAssertEqual(list.offsetMap.sourceInsertionOffset(forReaderOffset: 0), 0)

        let fenced = presentation("intro\n```swift\nlet x = 1\n```\n")
        let code = readerRange(of: "let x", in: fenced)
        XCTAssertEqual(
            fenced.offsetMap.sourceInsertionOffset(forReaderOffset: code.location),
            ("intro\n```swift\n" as NSString).length
        )
    }

    func testRevealedSyntaxIsEmittedOneToOneAndOtherSyntaxStaysHidden() throws {
        let text = "# Title\nSome **bold** and *em* text\n- item\n```\ncode\n```"
        let source = text as NSString
        let bold = source.range(of: "**bold**")
        let built = presentation(text, reveal: bold)
        let rendered = built.attributedString.string

        XCTAssertEqual(rendered, "Title\nSome **bold** and em text\n• item\ncode\n")
        let opening = (rendered as NSString).range(of: "**")
        let record = try XCTUnwrap(built.offsetMap.records.first {
            $0.readerRange == opening
        })
        XCTAssertEqual(record.role, .syntax)
        XCTAssertFalse(record.isSubstitution)
        XCTAssertTrue(record.isOneToOne)
        XCTAssertEqual(record.sourceRange, NSRange(location: bold.location, length: 2))
        let color = built.attributedString.attribute(.foregroundColor, at: opening.location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, ReaderTheme.default.secondaryColor)
        let font = try XCTUnwrap(
            built.attributedString.attribute(.font, at: opening.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertGreaterThan(NSFontManager.shared.weight(of: font), 5)
        XCTAssertEqual(
            built.attributedString.attribute(.ligature, at: opening.location, effectiveRange: nil) as? Int,
            0
        )
        XCTAssertEqual(
            built.offsetMap.sourceRange(forReaderRange: (rendered as NSString).range(of: "**bold**")),
            bold
        )

        let everything = presentation(text, reveal: NSRange(location: 0, length: source.length))
        XCTAssertEqual(
            everything.attributedString.string,
            "# Title\nSome **bold** and *em* text\n- item\n```\ncode\n```"
        )
        let link = "[link](https://x.y)"
        let revealedLink = presentation(link, reveal: NSRange(location: 0, length: (link as NSString).length))
        XCTAssertEqual(revealedLink.attributedString.string, link)
        XCTAssertNil(revealedLink.attributedString.attribute(.link, at: 0, effectiveRange: nil))
        XCTAssertNotNil(revealedLink.attributedString.attribute(.link, at: 1, effectiveRange: nil))
    }

    func testCommonAffixesNeverSplitSurrogatePairs() {
        let old = "ab🦊cd" as NSString
        let new = "ab🦋cd" as NSString
        let affixes = ReaderView.Coordinator.commonAffixes(old, new)
        XCTAssertEqual(affixes.prefix, 2)
        XCTAssertEqual(affixes.suffix, 2)
        let same = ReaderView.Coordinator.commonAffixes("abc", "abc")
        XCTAssertEqual(same.prefix, 3)
        XCTAssertEqual(same.suffix, 0)
        let grown = ReaderView.Coordinator.commonAffixes("ab", "aXb")
        XCTAssertEqual(grown.prefix, 1)
        XCTAssertEqual(grown.suffix, 1)
    }
}

/// Hosts the real container offscreen in formatted mode and edits the reader.
/// The window is never ordered front and no input events are synthesized.
final class RevealTransitionRemapTests: XCTestCase {
    /// Glyphs for every offset plus one substituted glyph (a list bullet) at
    /// `substitutedAt`, to check that substituted keys remap too.
    private func snapshot(offsets: Range<Int>, substitutedAt: Int = 100) -> RevealTransitionSnapshot {
        var glyphs: [RevealGlyphKey: RevealMeasuredGlyph] = [:]
        for offset in offsets {
            glyphs[.source(offset)] = RevealMeasuredGlyph(
                readerIndex: offset,
                box: MorphGlyphBox(
                    x: CGFloat(offset) * 10,
                    baseline: 0,
                    width: 10,
                    font: .systemFont(ofSize: 12),
                    attributed: NSAttributedString(string: "x")
                )
            )
        }
        glyphs[.substituted(sourceLocation: substitutedAt, index: 0)] = RevealMeasuredGlyph(
            readerIndex: 100,
            box: MorphGlyphBox(x: 1000, baseline: 0, width: 10, font: .systemFont(ofSize: 12), attributed: NSAttributedString(string: "•"))
        )
        return RevealTransitionSnapshot(glyphs: glyphs, measuredRanges: [NSRange(location: 0, length: offsets.count)])
    }

    private func edit(_ text: String, select fragment: String) -> MarkdownWrapToggle.Edit {
        MarkdownWrapToggle.edit(
            in: text as NSString,
            sourceMap: MarkdownSourceMap.parse(text),
            selection: (text as NSString).range(of: fragment),
            prefix: "**",
            suffix: "**"
        )
    }

    func testWrapRemapsEveryGlyphWithoutCollisionsOrDeletions() {
        let before = snapshot(offsets: 0..<14)
        let wrap = edit("Some bold text", select: "bold")
        let remapped = before.remapped(through: wrap.newOffset(forOldOffset:))

        XCTAssertEqual(remapped.glyphs.count + remapped.deleted.count, before.glyphs.count, "no key collides")
        XCTAssertTrue(remapped.deleted.isEmpty)
        XCTAssertEqual(remapped.glyphs[.source(7)]?.readerIndex, 5, "the b of bold now sits past the prefix")
        XCTAssertEqual(remapped.glyphs[.source(13)]?.readerIndex, 9)
        XCTAssertNil(remapped.glyphs[.source(5)])
        XCTAssertEqual(remapped.glyphs[.substituted(sourceLocation: 104, index: 0)]?.readerIndex, 100)
    }

    func testUnwrapRemapsTheContentAndKeepsTheDelimitersForFadingOut() {
        let before = snapshot(offsets: 0..<18)
        let unwrap = edit("Some **bold** text", select: "bold")
        let remapped = before.remapped(through: unwrap.newOffset(forOldOffset:))

        XCTAssertEqual(remapped.glyphs.count + remapped.deleted.count, before.glyphs.count, "no key collides")
        XCTAssertEqual(Set(remapped.deleted.keys), [.source(5), .source(6), .source(11), .source(12)])
        XCTAssertEqual(remapped.glyphs[.source(5)]?.readerIndex, 7)
        XCTAssertEqual(remapped.glyphs[.source(9)]?.readerIndex, 13)

        XCTAssertEqual(remapped.glyphs[.substituted(sourceLocation: 96, index: 0)]?.readerIndex, 100)
        let plan = RevealTransitionPlanner.plan(before: remapped, after: snapshot(offsets: 0..<14, substitutedAt: 96))
        XCTAssertEqual(plan.fadeOutCount, 4, "the removed delimiters fade out")
        XCTAssertEqual(plan.fadeInCount, 0)
    }
}

final class FormattedEditingContainerTests: XCTestCase {
    private struct Host {
        let document: Document
        let window: NSWindow
        let hosting: NSHostingView<EditorContainerView>
        let reader: ReaderNSTextView
        let coordinator: ReaderView.Coordinator

        func pump(seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                hosting.layoutSubtreeIfNeeded()
            }
        }

        func readerRange(of fragment: String) throws -> NSRange {
            let range = (reader.string as NSString).range(of: fragment)
            XCTAssertNotEqual(range.location, NSNotFound, "missing \(fragment) in reader")
            return range
        }

        func placeCaret(at offset: Int) {
            reader.setSelectedRange(NSRange(location: offset, length: 0))
        }

        func type(_ string: String) {
            reader.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
        }

        var layoutManager: ReaderLayoutManager? {
            reader.layoutManager as? ReaderLayoutManager
        }

        /// Overlay layers whose text is `character`, with their travel.
        func transitionEntries(for character: String) -> [RevealTransitionOverlay.ActiveEntry] {
            (coordinator.revealTransition?.activeEntries ?? []).filter { $0.entry.text.string == character }
        }
    }

    private var hosts: [Host] = []

    override func tearDown() {
        for host in hosts {
            host.window.orderOut(nil)
        }
        hosts.removeAll()
        super.tearDown()
    }

    private func makeHost(text: String, size: NSSize = NSSize(width: 900, height: 700)) throws -> Host {
        let document = Document(rawText: text)
        document.headings = MarkdownSourceMap.parse(text).headings
        document.mode = .preview

        let hosting = NSHostingView(rootView: EditorContainerView(
            document: document,
            configuration: .default,
            scrollToHeading: nil,
            isSelected: true
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        // Never ordered front: the operator is using the machine.
        var reader: ReaderNSTextView?
        for _ in 0..<100 where reader == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            hosting.layoutSubtreeIfNeeded()
            if let candidate = document.sharedReaderBridge.morphTextView(),
               document.sharedReaderBridge.morphPresentation() != nil,
               document.sharedEditorBridge.morphTextView() != nil {
                reader = candidate
            }
        }
        let readerView = try XCTUnwrap(reader, "reader should be mounted")
        let coordinator = try XCTUnwrap(document.sharedReaderBridge.coordinator)
        coordinator.playsRefusalSound = false
        let host = Host(
            document: document,
            window: window,
            hosting: hosting,
            reader: readerView,
            coordinator: coordinator
        )
        host.pump(seconds: 0.1)
        hosts.append(host)
        return host
    }

    func testTypingInAParagraphEditsTheSourceAndKeepsTheCaretAfterIt() throws {
        let host = try makeHost(text: "Hello world\n")
        host.placeCaret(at: 5)
        host.type(",")

        XCTAssertEqual(host.document.rawText, "Hello, world\n")
        XCTAssertEqual(host.reader.string, "Hello, world\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertTrue(host.document.isDirty)
        XCTAssertEqual(host.document.sharedEditorBridge.morphTextView()?.string, "Hello, world\n")
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
    }

    func testCaretInsideBoldRevealsSyntaxAndTypingStaysInside() throws {
        let host = try makeHost(text: "Some **bold** text")
        XCTAssertEqual(host.reader.string, "Some bold text")

        let bold = try host.readerRange(of: "bold")
        host.placeCaret(at: bold.location + 2)
        XCTAssertEqual(host.reader.string, "Some **bold** text")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 9, length: 0))

        host.type("X")
        XCTAssertEqual(host.document.rawText, "Some **boXld** text")
        XCTAssertEqual(host.reader.string, "Some **boXld** text")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 10, length: 0))

        // Leaving the construct hides its syntax again.
        host.placeCaret(at: 0)
        XCTAssertEqual(host.reader.string, "Some boXld text")
    }

    func testTypingAtTheVisibleCaretAfterRevealedSyntaxLandsOutsideTheConstruct() throws {
        let host = try makeHost(text: "Some **bold** text")
        let bold = try host.readerRange(of: "bold")
        host.placeCaret(at: NSMaxRange(bold))
        XCTAssertEqual(host.reader.string, "Some **bold** text")
        // The caret sticks to the "d" it was next to, before the closing marks.
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 11, length: 0))

        host.placeCaret(at: 13)
        host.type("X")
        XCTAssertEqual(host.document.rawText, "Some **bold**X text")
        // The caret is now outside the construct, so its syntax hides again.
        XCTAssertEqual(host.reader.string, "Some boldX text")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 10, length: 0))
    }

    func testBackspaceAtTheEndOfABoldWordRemovesOnlyThatCharacter() throws {
        let host = try makeHost(text: "Some **bold** text")
        let bold = try host.readerRange(of: "bold")
        host.placeCaret(at: NSMaxRange(bold))
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "Some **bol** text")
        XCTAssertEqual(host.reader.string, "Some **bol** text")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 10, length: 0))
    }

    func testDeletingASelectionAcrossHiddenSyntaxRemovesTheSyntaxToo() throws {
        let host = try makeHost(text: "Some **bold** text")
        let selection = try host.readerRange(of: " bold ")
        host.reader.setSelectedRange(selection)
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "Sometext")
        XCTAssertEqual(host.reader.string, "Sometext")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testTypingOverAListMarkerIsRefusedButASelectionOverItDeletesItsSource() throws {
        let host = try makeHost(text: "- item\n- two\n\nAfter")
        host.placeCaret(at: try host.readerRange(of: "After").location)
        host.pump(seconds: 0.05)
        XCTAssertEqual(host.reader.string, "• item\n• two\n\nAfter")
        let marker = try host.readerRange(of: "• item")
        host.reader.setSelectedRange(marker)
        host.type("x")
        XCTAssertEqual(host.document.rawText, "- item\n- two\n\nAfter")
        XCTAssertEqual(host.reader.string, "• item\n• two\n\nAfter")
        XCTAssertEqual(host.coordinator.refusedEditCount, 1)

        host.reader.setSelectedRange(try host.readerRange(of: "• two"))
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "- item\n\n\nAfter", "the bullet's whole source goes with the selection")
        XCTAssertEqual(host.coordinator.refusedEditCount, 1)
    }

    func testBackspaceIntoATaskBoxOrAThematicBreakRemovesTheWholeConstruct() throws {
        let host = try makeHost(text: "- [ ] task\n\nbefore\n\n---\n\nafter")
        host.placeCaret(at: try host.readerRange(of: "before").location)
        host.pump(seconds: 0.05)
        XCTAssertEqual(host.reader.string, "☐ task\n\nbefore\n\n\u{200B}\n\nafter")
        host.reader.setSelectedRange(NSRange(location: 1, length: 1))
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "task\n\nbefore\n\n---\n\nafter", "the box and its marker go together")
        host.placeCaret(at: try host.readerRange(of: "before").location)
        host.pump(seconds: 0.05)
        XCTAssertEqual(host.reader.string, "task\n\nbefore\n\n\u{200B}\n\nafter")

        let rule = try host.readerRange(of: "\u{200B}")
        host.placeCaret(at: NSMaxRange(rule))
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "task\n\nbefore\n\n\n\nafter")
        XCTAssertEqual(host.reader.string, "task\n\nbefore\n\n\n\nafter")
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
    }

    func testBackspaceIntoTheFrontMatterRemovesItAndTypingIntoItIsRefused() throws {
        let host = try makeHost(text: "---\ntitle: x\n---\nbody")
        let title = try host.readerRange(of: "title")
        host.placeCaret(at: title.location + 2)
        host.type("y")
        XCTAssertEqual(host.document.rawText, "---\ntitle: x\n---\nbody")
        XCTAssertEqual(host.coordinator.refusedEditCount, 1)

        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "\nbody")
        XCTAssertEqual(host.reader.string, "\nbody")
        XCTAssertEqual(host.coordinator.refusedEditCount, 1)
    }

    func testEnterAtTheEndOfAListItemStartsTheNextItemAndEnterOnAnEmptyItemEndsTheList() throws {
        let host = try makeHost(text: "- item")
        host.placeCaret(at: 6)
        host.reader.insertNewline(nil)
        XCTAssertEqual(host.document.rawText, "- item\n- ")
        XCTAssertEqual(host.reader.string, "• item\n- ", "the new item's marker is revealed under the caret")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 9, length: 0))

        host.reader.insertNewline(nil)
        XCTAssertEqual(host.document.rawText, "- item\n")
        XCTAssertEqual(host.reader.string, "• item\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 7, length: 0))
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
    }

    func testEnterContinuesOrderedTaskAndQuoteLines() throws {
        let ordered = try makeHost(text: "1. one")
        ordered.placeCaret(at: 6)
        ordered.reader.insertNewline(nil)
        XCTAssertEqual(ordered.document.rawText, "1. one\n2. ")
        XCTAssertEqual(ordered.reader.string, "1. one\n2. ")
        XCTAssertEqual(ordered.reader.selectedRange(), NSRange(location: 10, length: 0))

        let task = try makeHost(text: "- [ ] task")
        task.placeCaret(at: 6)
        task.reader.insertNewline(nil)
        XCTAssertEqual(task.document.rawText, "- [ ] task\n- [ ] ")
        XCTAssertEqual(task.reader.string, "☐ task\n- [ ] ")
        XCTAssertEqual(task.reader.selectedRange(), NSRange(location: 13, length: 0))

        let quote = try makeHost(text: "> quote")
        quote.placeCaret(at: 5)
        XCTAssertEqual(quote.reader.string, "> quote", "the caret inside the quote reveals its marker")
        quote.placeCaret(at: 7)
        quote.reader.insertNewline(nil)
        XCTAssertEqual(quote.document.rawText, "> quote\n> ")
        XCTAssertEqual(quote.reader.string, "> quote\n> ")
        XCTAssertEqual(quote.reader.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertEqual(quote.coordinator.refusedEditCount, 0)
    }

    func testEnterInAParagraphStartsANewParagraph() throws {
        let host = try makeHost(text: "Hello world")
        host.placeCaret(at: 6)
        host.reader.insertNewline(nil)
        XCTAssertEqual(host.document.rawText, "Hello \n\nworld")
        XCTAssertEqual(host.reader.string, "Hello \n\nworld")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 8, length: 0))
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
    }

    func testEnterAtTheEndOfAHeadingLeavesABlankLineAndACaretOnANewLine() throws {
        let host = try makeHost(text: "# Title")
        host.placeCaret(at: 5)
        XCTAssertEqual(host.reader.string, "# Title")
        host.placeCaret(at: 7)
        host.reader.insertNewline(nil)
        XCTAssertEqual(host.document.rawText, "# Title\n\n")
        XCTAssertEqual(host.reader.string, "Title\n\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 7, length: 0))
    }

    func testEnterInsideAFencedCodeBlockInsertsASingleNewline() throws {
        let host = try makeHost(text: "```\ncode\n```\n")
        let code = try host.readerRange(of: "code")
        host.placeCaret(at: code.location + 2)
        host.reader.insertNewline(nil)
        XCTAssertEqual(host.document.rawText, "```\nco\nde\n```\n")
        // The caret is inside the block, so its fences show around the code.
        XCTAssertEqual(host.reader.string, "```\nco\nde\n```\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 7, length: 0))
    }

    func testCaretInsideAFencedBlockShowsTheFencesAndTypingRoutesInside() throws {
        let host = try makeHost(text: "Intro\n\n```swift\nlet x = 1\n```\n\nAfter\n")
        XCTAssertEqual(host.reader.string, "Intro\n\nlet x = 1\n\nAfter\n")

        let code = try host.readerRange(of: "let x")
        host.placeCaret(at: code.location + 4)
        XCTAssertEqual(host.reader.string, "Intro\n\n```swift\nlet x = 1\n```\n\nAfter\n")
        // The caret keeps its source position, now past the shown fence line.
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: try host.readerRange(of: "let x").location + 4, length: 0))

        host.type("X")
        XCTAssertEqual(host.document.rawText, "Intro\n\n```swift\nlet Xx = 1\n```\n\nAfter\n")
        XCTAssertEqual(host.reader.string, "Intro\n\n```swift\nlet Xx = 1\n```\n\nAfter\n")
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)

        // Editing the info string on the shown fence line routes there too.
        let info = try host.readerRange(of: "swift")
        host.placeCaret(at: NSMaxRange(info))
        host.type("!")
        XCTAssertEqual(host.document.rawText, "Intro\n\n```swift!\nlet Xx = 1\n```\n\nAfter\n")
        XCTAssertTrue(host.reader.string.contains("```swift!\n"))

        // Leaving the block hides the fences again.
        host.placeCaret(at: 0)
        XCTAssertEqual(host.reader.string, "Intro\n\nlet Xx = 1\n\nAfter\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 0, length: 0))

        // A caret on the empty line after the block does not reveal it.
        let after = try host.readerRange(of: "After")
        host.placeCaret(at: after.location - 1)
        XCTAssertEqual(host.reader.string, "Intro\n\nlet Xx = 1\n\nAfter\n")
    }

    func testCaretInsideAQuoteShowsItsMarkers() throws {
        let host = try makeHost(text: "Intro\n\n> one\n> two\n")
        XCTAssertEqual(host.reader.string, "Intro\n\none\ntwo\n")
        let two = try host.readerRange(of: "two")
        host.placeCaret(at: two.location + 1)
        XCTAssertEqual(host.reader.string, "Intro\n\n> one\n> two\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: try host.readerRange(of: "two").location + 1, length: 0))
        host.type("X")
        XCTAssertEqual(host.document.rawText, "Intro\n\n> one\n> tXwo\n")
        host.placeCaret(at: 0)
        XCTAssertEqual(host.reader.string, "Intro\n\none\ntXwo\n")
    }

    func testAListMarkerRevealsWhileTheCaretIsOnItsItem() throws {
        let host = try makeHost(text: "- item\n- two\n\nAfter")
        XCTAssertEqual(host.reader.string, "• item\n• two\n\nAfter")
        host.placeCaret(at: try host.readerRange(of: "item").location)
        host.pump(seconds: 0.05)
        XCTAssertEqual(host.reader.string, "- item\n• two\n\nAfter")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 2, length: 0), "the caret stays on the same source character")
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "-item\n- two\n\nAfter", "the revealed marker deletes character by character")
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "item\n- two\n\nAfter")
        host.placeCaret(at: try host.readerRange(of: "After").location)
        host.pump(seconds: 0.05)
        XCTAssertEqual(host.reader.string, "item\n• two\n\nAfter")
    }

    func testCommandZAndShiftCommandZReachTheDocumentHistoryFromTheReader() throws {
        let host = try makeHost(text: "Hello world")
        host.window.makeFirstResponder(host.reader)
        host.placeCaret(at: 5)
        host.type("!")
        XCTAssertEqual(host.document.rawText, "Hello! world")
        XCTAssertTrue(host.reader.tryToPerform(Selector(("undo:")), with: nil))
        host.pump(seconds: 0.1)
        XCTAssertEqual(host.document.rawText, "Hello world")
        XCTAssertEqual(host.reader.string, "Hello world")
        XCTAssertTrue(host.reader.tryToPerform(Selector(("redo:")), with: nil))
        host.pump(seconds: 0.1)
        XCTAssertEqual(host.document.rawText, "Hello! world")
        XCTAssertEqual(host.reader.string, "Hello! world")
        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "")
        XCTAssertTrue(host.reader.validateUserInterfaceItem(undoItem))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "")
        XCTAssertFalse(host.reader.validateUserInterfaceItem(redoItem))
    }

    @MainActor
    func testFindSelectsMatchesInTheFormattedTextAndWraps() throws {
        let host = try makeHost(text: "One **two** three\n\ntwo again")
        let controller = FindController()
        controller.attach(editorBridge: host.document.sharedEditorBridge, readerBridge: host.document.sharedReaderBridge, mode: .preview)
        controller.searchText = "TWO"
        controller.findNext()
        XCTAssertTrue(controller.lastMatchFound)
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "two"), "matches the formatted text, not the source")
        controller.findNext()
        let second = (host.reader.string as NSString).range(of: "two again")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: second.location, length: 3))
        controller.findNext()
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "two"), "wraps around")
        controller.searchText = "**"
        controller.findNext()
        XCTAssertFalse(controller.lastMatchFound, "hidden syntax is not searchable in formatted mode")
    }

    func testUndoThroughTheDocumentUndoManagerRestoresSourceAndReader() throws {
        let host = try makeHost(text: "Hello world")
        XCTAssertIdentical(host.reader.undoManager, host.document.undoManager)
        host.placeCaret(at: 5)
        host.type("!")
        XCTAssertEqual(host.document.rawText, "Hello! world")
        XCTAssertTrue(host.document.undoManager.canUndo)

        host.document.undoManager.undo()
        host.pump(seconds: 0.1)
        XCTAssertEqual(host.document.rawText, "Hello world")
        XCTAssertEqual(host.reader.string, "Hello world")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 5, length: 0))

        host.document.undoManager.redo()
        host.pump(seconds: 0.1)
        XCTAssertEqual(host.document.rawText, "Hello! world")
        XCTAssertEqual(host.reader.string, "Hello! world")
    }

    func testAnEditFarFromTheViewportTopDoesNotMoveTheScrollPosition() throws {
        let text = (0..<200).map { "Line \($0) has some words in it." }.joined(separator: "\n")
        let host = try makeHost(text: text)
        let scrollView = try XCTUnwrap(host.reader.enclosingScrollView)
        host.document.sharedReaderBridge.scrollToRatio(0.5)
        host.pump(seconds: 0.05)
        let origin = scrollView.contentView.bounds.origin
        XCTAssertGreaterThan(origin.y, 100)

        let centerLine = try XCTUnwrap(host.document.sharedReaderBridge.currentSourceLineAtViewportCenter())
        let presentation = try XCTUnwrap(host.document.sharedReaderBridge.morphPresentation())
        let lineRange = try XCTUnwrap(presentation.offsetMap.readerRange(forSourceLine: centerLine))
        host.placeCaret(at: NSMaxRange(lineRange))
        host.type(" more")
        XCTAssertTrue(host.document.rawText.contains("Line \(centerLine) has some words in it. more"))
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, origin.y, accuracy: 0.5)
        host.pump(seconds: 0.2)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, origin.y, accuracy: 0.5)
    }

    func testCompositionCommitsToTheSourceExactlyOnce() throws {
        let host = try makeHost(text: "Hello world")
        host.placeCaret(at: 5)
        let anywhere = NSRange(location: NSNotFound, length: 0)
        host.reader.setMarkedText("ㅎ", selectedRange: NSRange(location: 0, length: 1), replacementRange: anywhere)
        XCTAssertTrue(host.reader.hasMarkedText())
        XCTAssertEqual(host.document.rawText, "Hello world")
        XCTAssertEqual(host.reader.string, "Helloㅎ world")
        host.reader.setMarkedText("하", selectedRange: NSRange(location: 0, length: 1), replacementRange: anywhere)
        XCTAssertEqual(host.reader.string, "Hello하 world")
        XCTAssertEqual(host.document.rawText, "Hello world")

        host.reader.insertText("한", replacementRange: anywhere)
        XCTAssertFalse(host.reader.hasMarkedText())
        XCTAssertEqual(host.document.rawText, "Hello한 world")
        XCTAssertEqual(host.reader.string, "Hello한 world")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)

        host.document.undoManager.undo()
        host.pump(seconds: 0.1)
        XCTAssertEqual(host.document.rawText, "Hello world")
        XCTAssertFalse(host.document.undoManager.canUndo)
    }

    func testRevealRebuildTimeForTenThousandCharacters() throws {
        var text = ""
        var index = 0
        while (text as NSString).length < 10_000 {
            text += "Paragraph \(index) with **bold \(index)** words and `code` inside it.\n\n"
            index += 1
        }
        let host = try makeHost(text: text)

        // A reveal in view, with the rest of the viewport below it: the
        // paragraphs below are measured so they can slide if the reveal
        // re-wraps the paragraph.
        let visibleTarget = try host.readerRange(of: "bold 1")
        let visibleReveal = ContinuousClock().measure {
            host.placeCaret(at: visibleTarget.location + 2)
        }
        let visibleMilliseconds = Double(visibleReveal.components.seconds) * 1_000
            + Double(visibleReveal.components.attoseconds) / 1e15
        print("Formatted editing 10,000-character reveal rebuild in view: \(visibleMilliseconds) ms")
        print("Formatted editing 10,000-character reveal transition in view: \(host.coordinator.lastRevealTransitionOutcome)")
        XCTAssertTrue(host.reader.string.contains("**bold 1**"))
        host.pump(seconds: 0.3)

        let target = try host.readerRange(of: "bold 40")
        var elapsed: Duration = .zero
        elapsed = ContinuousClock().measure {
            host.placeCaret(at: target.location + 2)
        }
        XCTAssertTrue(host.reader.string.contains("**bold 40**"))
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1e15
        print("Formatted editing 10,000-character reveal rebuild: \(milliseconds) ms")
        print("Formatted editing 10,000-character reveal transition: \(host.coordinator.lastRevealTransitionOutcome)")

        let typing = ContinuousClock().measure {
            host.type("X")
        }
        let typingMilliseconds = Double(typing.components.seconds) * 1_000
            + Double(typing.components.attoseconds) / 1e15
        print("Formatted editing 10,000-character keystroke: \(typingMilliseconds) ms")
        XCTAssertTrue(host.document.rawText.contains("**boXld 40**"))

        let heading = ContinuousClock().measure {
            host.reader.applyHeading1()
        }
        let headingMilliseconds = Double(heading.components.seconds) * 1_000
            + Double(heading.components.attoseconds) / 1e15
        print("Formatted editing 10,000-character heading command: \(headingMilliseconds) ms")
        print("Formatted editing 10,000-character heading transition: \(host.coordinator.lastRevealTransitionOutcome)")
        XCTAssertTrue(host.document.rawText.contains("# Paragraph 40 with **boXld 40**"))
    }

    // MARK: - Reveal transition

    private func skipUnlessTransitionsRun() throws {
        try XCTSkipIf(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "Reduce Motion keeps the instant swap"
        )
    }

    func testCaretIntoBoldFadesTheSyntaxInWhileTheFollowingTextSlides() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Some **bold** text")
        let bold = try host.readerRange(of: "bold")
        host.placeCaret(at: bold.location + 2)

        XCTAssertEqual(host.reader.string, "Some **bold** text")
        let overlay = try XCTUnwrap(host.coordinator.revealTransition, "overlay should exist")
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        XCTAssertTrue(overlay.lastOutcome.hasPrefix("animating"), overlay.lastOutcome)
        XCTAssertTrue(overlay.superview === host.reader, "overlay lives inside the reader text view")
        XCTAssertGreaterThan(overlay.layer?.sublayers?.count ?? 0, 0)
        XCTAssertFalse(host.layoutManager?.hiddenCharacterRanges.isEmpty ?? true, "real glyphs should be hidden")

        let stars = host.transitionEntries(for: "*")
        XCTAssertEqual(stars.count, 4, "four asterisks appear")
        XCTAssertTrue(stars.allSatisfy { $0.entry.from == nil && $0.entry.to != nil }, "asterisks fade in")
        let trailing = host.transitionEntries(for: "t")
        XCTAssertFalse(trailing.isEmpty, "the text after the bold word moves")
        XCTAssertTrue(trailing.allSatisfy { $0.entry.isMover && $0.to.x > $0.from.x }, "it moves right")

        host.pump(seconds: 0.06)
        XCTAssertTrue(overlay.isRunning, "still animating after 60 ms")
        for star in stars {
            let opacity = try XCTUnwrap(star.layer.presentation()?.opacity)
            XCTAssertGreaterThan(opacity, 0)
            XCTAssertLessThan(opacity, 1)
        }
        for mover in trailing {
            let x = try XCTUnwrap(mover.layer.presentation()?.position.x)
            XCTAssertGreaterThan(x, mover.from.x)
            XCTAssertLessThan(x, mover.to.x)
        }

        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertNil(overlay.superview, "overlay should be removed when the animation ends")
        XCTAssertEqual(overlay.layer?.sublayers?.count ?? 0, 0)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 9, length: 0))
    }

    func testCaretLeavingBoldFadesTheSyntaxOutWhileTheTextSlidesBack() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Some **bold** text")
        let bold = try host.readerRange(of: "bold")
        host.placeCaret(at: bold.location + 2)
        host.pump(seconds: 0.4)
        XCTAssertEqual(host.reader.string, "Some **bold** text")

        host.placeCaret(at: 0)
        XCTAssertEqual(host.reader.string, "Some bold text")
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        let stars = host.transitionEntries(for: "*")
        XCTAssertEqual(stars.count, 4)
        XCTAssertTrue(stars.allSatisfy { $0.entry.from != nil && $0.entry.to == nil }, "asterisks fade out")
        let trailing = host.transitionEntries(for: "t")
        XCTAssertTrue(trailing.allSatisfy { $0.entry.isMover && $0.to.x < $0.from.x }, "text slides back left")

        host.pump(seconds: 0.06)
        for star in stars {
            let opacity = try XCTUnwrap(star.layer.presentation()?.opacity)
            XCTAssertGreaterThan(opacity, 0)
            XCTAssertLessThan(opacity, 1)
        }

        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertNil(overlay.superview)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
    }

    func testFinishingARevealRedrawsTheRealGlyphsBeforeTheCopiesGo() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Reduce Motion disables the animation")
        let host = try makeHost(text: "Some **bold** text and more words here\n")
        host.placeCaret(at: 7)
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        XCTAssertFalse(host.layoutManager?.hiddenCharacterRanges.isEmpty ?? true)

        // No run-loop turn in between: the redraw must already have happened
        // when the copies are gone, or the frame that removes them is blank.
        overlay.finishImmediately()
        XCTAssertFalse(overlay.isRunning)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
        XCTAssertFalse(host.reader.needsDisplay, "real glyphs should be redrawn synchronously")
        XCTAssertNil(overlay.superview)
    }

    func testTypingDuringARevealAnimationFinishesItFirst() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Some **bold** text")
        let bold = try host.readerRange(of: "bold")
        host.placeCaret(at: bold.location + 2)
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning)

        host.type("X")
        XCTAssertEqual(host.document.rawText, "Some **boXld** text")
        XCTAssertEqual(host.reader.string, "Some **boXld** text")
        XCTAssertFalse(overlay.isRunning, "a keystroke ends the animation")
        XCTAssertNil(overlay.superview)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
        XCTAssertEqual(host.coordinator.lastRevealTransitionOutcome, "skipped: not a caret move")
    }

    func testKeystrokesInsideRevealedSyntaxDoNotAnimate() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Some **bold** text")
        let bold = try host.readerRange(of: "bold")
        host.placeCaret(at: bold.location + 2)
        host.pump(seconds: 0.4)

        host.type("X")
        XCTAssertEqual(host.reader.string, "Some **boXld** text")
        XCTAssertEqual(host.coordinator.lastRevealTransitionOutcome, "skipped: not a caret move")
        XCTAssertFalse(host.coordinator.revealTransition?.isRunning ?? false)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])

        // A caret move that keeps the same reveal does not rebuild or animate.
        host.placeCaret(at: bold.location + 3)
        XCTAssertFalse(host.coordinator.revealTransition?.isRunning ?? false)
    }

    // MARK: - Wrap commands

    private func isBold(_ font: NSFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    func testBoldOnASelectedWordFadesTheDelimitersInAndCrossfadesTheWord() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Some bold text")
        host.reader.setSelectedRange(try host.readerRange(of: "bold"))

        host.reader.wrapSelection(prefix: "**", suffix: "**")

        XCTAssertEqual(host.document.rawText, "Some **bold** text")
        XCTAssertEqual(host.reader.string, "Some **bold** text")
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "bold"), "the content is reselected at once")
        let overlay = try XCTUnwrap(host.coordinator.revealTransition, "overlay should exist")
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        XCTAssertTrue(overlay.lastOutcome.contains("4 restyling"), overlay.lastOutcome)
        XCTAssertFalse(host.layoutManager?.hiddenCharacterRanges.isEmpty ?? true, "real glyphs should be hidden")

        let stars = host.transitionEntries(for: "*")
        XCTAssertEqual(stars.count, 4, "both delimiter pairs appear")
        XCTAssertTrue(stars.allSatisfy { $0.entry.from == nil && $0.entry.to != nil }, "delimiters fade in")
        let word = ["b", "o", "l", "d"].flatMap { host.transitionEntries(for: $0) }
        XCTAssertEqual(word.count, 4)
        for glyph in word {
            XCTAssertTrue(glyph.entry.isMover && glyph.entry.crossfades, "\(glyph.entry.text.string) crossfades")
            XCTAssertFalse(isBold(glyph.entry.from?.font), "old styling is regular")
            XCTAssertTrue(isBold(glyph.entry.to?.font), "new styling is bold")
            XCTAssertNotNil(glyph.fromLayer, "a copy in the old styling fades out")
            XCTAssertGreaterThan(glyph.to.x, glyph.from.x, "the word slides right past the prefix")
        }
        let trailing = host.transitionEntries(for: "x")
        XCTAssertFalse(trailing.isEmpty, "the text after the word moves")
        XCTAssertTrue(trailing.allSatisfy { $0.entry.isMover && !$0.entry.crossfades && $0.to.x > $0.from.x })

        host.pump(seconds: 0.06)
        XCTAssertTrue(overlay.isRunning, "still animating after 60 ms")
        for glyph in word {
            let fading = try XCTUnwrap(glyph.fromLayer?.presentation()?.opacity)
            let appearing = try XCTUnwrap(glyph.layer.presentation()?.opacity)
            XCTAssertGreaterThan(fading, 0)
            XCTAssertLessThan(fading, 1)
            XCTAssertGreaterThan(appearing, 0)
            XCTAssertLessThan(appearing, 1)
        }

        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertNil(overlay.superview)
        XCTAssertEqual(overlay.layer?.sublayers?.count ?? 0, 0)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "bold"))
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
    }

    func testBoldAgainFadesTheDelimitersOutAndCrossfadesTheWordBack() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Some bold text")
        host.reader.setSelectedRange(try host.readerRange(of: "bold"))
        host.reader.wrapSelection(prefix: "**", suffix: "**")
        host.pump(seconds: 0.4)
        XCTAssertEqual(host.reader.string, "Some **bold** text")

        host.reader.wrapSelection(prefix: "**", suffix: "**")

        XCTAssertEqual(host.document.rawText, "Some bold text")
        XCTAssertEqual(host.reader.string, "Some bold text")
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "bold"))
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        let stars = host.transitionEntries(for: "*")
        XCTAssertEqual(stars.count, 4)
        XCTAssertTrue(stars.allSatisfy { $0.entry.from != nil && $0.entry.to == nil }, "delimiters fade out")
        let word = ["b", "o", "l", "d"].flatMap { host.transitionEntries(for: $0) }
        XCTAssertEqual(word.count, 4)
        for glyph in word {
            XCTAssertTrue(glyph.entry.crossfades)
            XCTAssertTrue(isBold(glyph.entry.from?.font))
            XCTAssertFalse(isBold(glyph.entry.to?.font))
            XCTAssertLessThan(glyph.to.x, glyph.from.x, "the word slides back left")
        }

        host.pump(seconds: 0.06)
        for star in stars {
            let opacity = try XCTUnwrap(star.layer.presentation()?.opacity)
            XCTAssertGreaterThan(opacity, 0)
            XCTAssertLessThan(opacity, 1)
        }

        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertNil(overlay.superview)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
    }

    func testItalicWithACaretFadesTwoDelimitersInWhileTheFollowingTextSlides() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Hello world")
        host.placeCaret(at: 5)

        host.reader.wrapSelection(prefix: "*", suffix: "*")

        XCTAssertEqual(host.reader.string, "Hello** world")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 6, length: 0))
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        let stars = host.transitionEntries(for: "*")
        XCTAssertEqual(stars.count, 2)
        XCTAssertTrue(stars.allSatisfy { $0.entry.from == nil && $0.entry.to != nil })
        let following = host.transitionEntries(for: "w")
        XCTAssertEqual(following.count, 1)
        XCTAssertTrue(following.allSatisfy { $0.entry.isMover && !$0.entry.crossfades && $0.to.x > $0.from.x })
        XCTAssertTrue(host.transitionEntries(for: "H").isEmpty, "text before the caret stays put")

        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
    }

    func testEnterDoesNotAnimate() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Hello world")
        host.placeCaret(at: 5)
        host.reader.insertNewline(nil)
        XCTAssertEqual(host.document.rawText, "Hello\n\n world")
        XCTAssertEqual(host.coordinator.lastRevealTransitionOutcome, "skipped: not a caret move")
        XCTAssertFalse(host.coordinator.revealTransition?.isRunning ?? false)
    }

    func testEnterOnAListItemFadesTheNewBulletIn() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "- item\n\nBelow paragraph\n")
        host.placeCaret(at: 6)
        host.reader.insertNewline(nil)
        XCTAssertEqual(host.document.rawText, "- item\n- \n\nBelow paragraph\n")
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        let bullets = host.transitionEntries(for: "•")
        XCTAssertEqual(bullets.filter { $0.entry.from == nil && $0.entry.to != nil }.count, 1, "the new bullet fades in")
        XCTAssertEqual(bullets.filter { $0.entry.to == nil }.count, 0)
        XCTAssertEqual(below(host, letter: "B").count, 1, "the paragraph below slides")
        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertNil(overlay.superview)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
    }

    func testDeletingABulletFadesItOut() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "- item\n\nBelow paragraph\n")
        host.placeCaret(at: try host.readerRange(of: "Below").location)
        host.pump(seconds: 0.4)
        XCTAssertEqual(host.reader.string, "• item\n\nBelow paragraph\n")
        host.reader.setSelectedRange(NSRange(location: 0, length: 2))
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "item\n\nBelow paragraph\n")
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        let bullets = host.transitionEntries(for: "•")
        XCTAssertEqual(bullets.filter { $0.entry.from != nil && $0.entry.to == nil }.count, 1, "the bullet fades out")
        let movers = host.transitionEntries(for: "i").filter { $0.entry.isMover }
        XCTAssertEqual(movers.count, 1, "the item's text slides")
        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertNil(overlay.superview)
        XCTAssertEqual(host.reader.string, "item\n\nBelow paragraph\n")
    }

    func testACaretJumpBetweenDistantParagraphsAnimatesBothParagraphs() throws {
        try skipUnlessTransitionsRun()
        var text = "First **one** here\n\n"
        for index in 0..<60 {
            text += "Filler paragraph \(index) with enough words to matter.\n\n"
        }
        text += "Last **two** there\n"
        let host = try makeHost(text: text)
        let one = try host.readerRange(of: "one")
        host.placeCaret(at: one.location + 1)
        host.pump(seconds: 0.4)

        let two = try host.readerRange(of: "two")
        host.placeCaret(at: two.location + 1)
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.lastOutcome.hasPrefix("animating"), overlay.lastOutcome)
        let stars = host.transitionEntries(for: "*")
        XCTAssertEqual(stars.filter { $0.entry.to == nil }.count, 4, "the first paragraph's syntax fades out")
        XCTAssertEqual(stars.filter { $0.entry.from == nil }.count, 4, "the last paragraph's syntax fades in")
        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
    }

    // MARK: - Heading commands

    private func pointSize(_ font: NSFont?) -> CGFloat {
        font?.pointSize ?? 0
    }

    /// Movers in the paragraph below a changed heading, by their first letter.
    private func below(_ host: Host, letter: String) -> [RevealTransitionOverlay.ActiveEntry] {
        host.transitionEntries(for: letter).filter { $0.entry.isMover && !$0.entry.crossfades }
    }

    func testHeadingOneOnAParagraphCrossfadesTheWordsFadesThePrefixInAndSlidesTheParagraphBelow() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Hello world\n\nBelow paragraph\n")
        host.placeCaret(at: 3)

        host.reader.applyHeading1()

        XCTAssertEqual(host.document.rawText, "# Hello world\n\nBelow paragraph\n")
        XCTAssertEqual(host.reader.string, "# Hello world\n\nBelow paragraph\n", "the prefix is revealed")
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "Hello world"))
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        XCTAssertTrue(overlay.lastOutcome.contains("paragraphs"), overlay.lastOutcome)

        let hash = host.transitionEntries(for: "#")
        XCTAssertEqual(hash.count, 1)
        XCTAssertTrue(hash.allSatisfy { $0.entry.from == nil && $0.entry.to != nil }, "the hash fades in")
        let prefixSpace = host.transitionEntries(for: " ").filter { $0.entry.key == .source(1) }
        XCTAssertEqual(prefixSpace.count, 1)
        XCTAssertTrue(prefixSpace.allSatisfy { $0.entry.from == nil }, "the space after it fades in")
        let word = ["H", "e", "l", "o"].flatMap { host.transitionEntries(for: $0) }
            .filter { (2..<7).map(RevealGlyphKey.source).contains($0.entry.key) }
        XCTAssertEqual(word.count, 5)
        XCTAssertTrue(word.allSatisfy { $0.entry.crossfades })
        for glyph in word {
            XCTAssertLessThan(pointSize(glyph.entry.from?.font), pointSize(glyph.entry.to?.font), "body to heading size")
            XCTAssertNotNil(glyph.fromLayer)
        }
        let belowMovers = below(host, letter: "B")
        XCTAssertEqual(belowMovers.count, 1, "the paragraph below moves")
        let mover = try XCTUnwrap(belowMovers.first)
        XCTAssertNotEqual(mover.from.y, mover.to.y)
        XCTAssertEqual(mover.from.x, mover.to.x, accuracy: 0.5)

        host.pump(seconds: 0.06)
        XCTAssertTrue(overlay.isRunning, "still animating after 60 ms")
        let y = try XCTUnwrap(mover.layer.presentation()?.position.y)
        XCTAssertGreaterThan(y, min(mover.from.y, mover.to.y))
        XCTAssertLessThan(y, max(mover.from.y, mover.to.y))

        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertNil(overlay.superview)
        XCTAssertEqual(overlay.layer?.sublayers?.count ?? 0, 0)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
        XCTAssertEqual(host.reader.string, "# Hello world\n\nBelow paragraph\n")
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "Hello world"))
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
    }

    func testHeadingTwoOnAHeadingKeepsTheHashAndFadesASecondOneIn() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Hello world\n\nBelow paragraph\n")
        host.placeCaret(at: 3)
        host.reader.applyHeading1()
        host.pump(seconds: 0.4)

        host.reader.applyHeading2()

        XCTAssertEqual(host.document.rawText, "## Hello world\n\nBelow paragraph\n")
        XCTAssertEqual(host.reader.string, "## Hello world\n\nBelow paragraph\n")
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        let hashes = host.transitionEntries(for: "#")
        XCTAssertEqual(hashes.count, 2)
        XCTAssertEqual(hashes.filter { $0.entry.from == nil }.count, 1, "one hash appears")
        XCTAssertEqual(hashes.filter { $0.entry.from != nil && $0.entry.to != nil }.count, 1, "the other stays")
        XCTAssertTrue(hashes.allSatisfy { $0.entry.to != nil }, "no hash fades out")
        let word = host.transitionEntries(for: "H")
        XCTAssertEqual(word.count, 1)
        XCTAssertTrue(word.allSatisfy { $0.entry.crossfades })
        XCTAssertGreaterThan(pointSize(word.first?.entry.from?.font), pointSize(word.first?.entry.to?.font))
        XCTAssertEqual(below(host, letter: "B").count, 1, "the paragraph below slides up")

        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "Hello world"))
    }

    func testParagraphOnAHeadingFadesThePrefixOutAndCrossfadesBackToTheBodyFont() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "## Hello world\n\nBelow paragraph\n")
        let hello = try host.readerRange(of: "Hello")
        host.placeCaret(at: hello.location + 1)
        host.pump(seconds: 0.4)
        XCTAssertEqual(host.reader.string, "## Hello world\n\nBelow paragraph\n")

        host.reader.applyParagraph()

        XCTAssertEqual(host.document.rawText, "Hello world\n\nBelow paragraph\n")
        XCTAssertEqual(host.reader.string, "Hello world\n\nBelow paragraph\n")
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "Hello world"))
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        let hashes = host.transitionEntries(for: "#")
        XCTAssertEqual(hashes.count, 2)
        XCTAssertTrue(hashes.allSatisfy { $0.entry.from != nil && $0.entry.to == nil }, "the prefix fades out")
        let word = host.transitionEntries(for: "H")
        XCTAssertEqual(word.count, 1)
        XCTAssertTrue(word.allSatisfy { $0.entry.crossfades })
        XCTAssertGreaterThan(pointSize(word.first?.entry.from?.font), pointSize(word.first?.entry.to?.font))
        XCTAssertEqual(below(host, letter: "B").count, 1)

        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertEqual(host.layoutManager?.hiddenCharacterRanges ?? [NSRange()], [])
    }

    func testHeadingCommandOnAnUnchangedLineOnlySelectsTheContent() throws {
        let host = try makeHost(text: "# Title\n\nbody")
        host.placeCaret(at: 2)
        host.pump(seconds: 0.4)
        let revision = host.document.textRevision
        host.reader.applyHeading1()
        XCTAssertEqual(host.document.textRevision, revision)
        XCTAssertEqual(host.reader.selectedRange(), try host.readerRange(of: "Title"))
        XCTAssertEqual(host.coordinator.refusedEditCount, 0)
        XCTAssertFalse(host.document.undoManager.canUndo)
    }

    func testTypingAHashIntoARevealedPrefixAnimatesAndTypingElsewhereDoesNot() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "# Title\n\nbody")
        host.placeCaret(at: 3)
        host.pump(seconds: 0.4)
        XCTAssertEqual(host.reader.string, "# Title\n\nbody")
        host.placeCaret(at: 0)
        XCTAssertFalse(host.coordinator.revealTransition?.isRunning ?? false, "the reveal is unchanged")

        host.type("#")

        XCTAssertEqual(host.document.rawText, "## Title\n\nbody")
        XCTAssertEqual(host.reader.string, "## Title\n\nbody")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 1, length: 0))
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        let hashes = host.transitionEntries(for: "#")
        XCTAssertEqual(hashes.count, 2)
        XCTAssertEqual(hashes.filter { $0.entry.from == nil }.count, 1, "the typed hash fades in")
        XCTAssertEqual(hashes.filter { $0.entry.isMover }.count, 1, "the old hash slides right")
        XCTAssertTrue(host.transitionEntries(for: "T").allSatisfy { $0.entry.crossfades }, "the title changes size")
        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)

        let body = try host.readerRange(of: "body")
        host.placeCaret(at: body.location + 2)
        host.pump(seconds: 0.4)
        host.type("x")
        XCTAssertEqual(host.document.rawText, "## Title\n\nboxdy")
        XCTAssertEqual(host.coordinator.lastRevealTransitionOutcome, "skipped: not a caret move")
        XCTAssertFalse(host.coordinator.revealTransition?.isRunning ?? false)
    }

    func testTypingDashSpaceStartsAListWithTheBulletFadingIn() throws {
        try skipUnlessTransitionsRun()
        let host = try makeHost(text: "Hello\n\nTail")
        host.placeCaret(at: 0)
        host.type("-")
        XCTAssertEqual(host.document.rawText, "-Hello\n\nTail")
        XCTAssertEqual(host.coordinator.lastRevealTransitionOutcome, "skipped: not a caret move", "a dash alone is plain text")

        host.type(" ")

        XCTAssertEqual(host.document.rawText, "- Hello\n\nTail")
        XCTAssertEqual(host.reader.string, "- Hello\n\nTail", "the marker stays revealed under the caret")
        let overlay = try XCTUnwrap(host.coordinator.revealTransition)
        XCTAssertTrue(overlay.isRunning, host.coordinator.lastRevealTransitionOutcome)
        XCTAssertTrue(host.transitionEntries(for: "H").allSatisfy { $0.entry.isMover })
        host.pump(seconds: 0.4)
        XCTAssertFalse(overlay.isRunning)
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 2, length: 0))

        host.placeCaret(at: try host.readerRange(of: "Tail").location)
        host.pump(seconds: 0.05)
        XCTAssertEqual(host.reader.string, "\u{2022} Hello\n\nTail", "the bullet appears once the caret leaves the item")
        let bullet = host.transitionEntries(for: "\u{2022}")
        XCTAssertEqual(bullet.count, 1)
        XCTAssertTrue(bullet.allSatisfy { $0.entry.from == nil }, "the bullet fades in")
        let dash = host.transitionEntries(for: "-")
        XCTAssertEqual(dash.count, 1)
        XCTAssertTrue(dash.allSatisfy { $0.entry.to == nil }, "the dash fades out")
        host.pump(seconds: 0.4)
    }

    func testHiddenCharacterRangesLeaveNoInkWhereTheGlyphsWere() throws {
        let host = try makeHost(text: "Some **bold** text")
        let layoutManager = try XCTUnwrap(host.layoutManager)
        let bold = try host.readerRange(of: "bold")
        let glyphRange = layoutManager.glyphRange(forCharacterRange: bold, actualCharacterRange: nil)
        let container = try XCTUnwrap(host.reader.textContainer)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x += host.reader.textContainerOrigin.x
        rect.origin.y += host.reader.textContainerOrigin.y
        rect = rect.insetBy(dx: 1, dy: 0)

        func inkPixelCount() throws -> Int {
            let rep = try XCTUnwrap(host.reader.bitmapImageRepForCachingDisplay(in: rect))
            host.reader.cacheDisplay(in: rect, to: rep)
            let background = host.reader.backgroundColor.usingColorSpace(.sRGB)
            var count = 0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if abs(color.redComponent - (background?.redComponent ?? 1)) > 0.1
                        || abs(color.greenComponent - (background?.greenComponent ?? 1)) > 0.1
                        || abs(color.blueComponent - (background?.blueComponent ?? 1)) > 0.1 {
                        count += 1
                    }
                }
            }
            return count
        }

        XCTAssertGreaterThan(try inkPixelCount(), 0, "the bold word draws")
        layoutManager.hiddenCharacterRanges = [bold]
        XCTAssertEqual(try inkPixelCount(), 0, "hidden characters draw nothing")
        layoutManager.hiddenCharacterRanges = []
        XCTAssertGreaterThan(try inkPixelCount(), 0, "the bold word draws again")
        XCTAssertEqual(layoutManager.morphGlyphOpacity, 1)
    }
}
