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
        XCTAssertNil(ReaderReveal.range(in: MarkdownSourceMap.parse(list), sourceCursor: 3))
    }
}

final class ReaderNewlineTests: XCTestCase {
    private func replacement(_ text: String, at offset: Int) -> String {
        ReaderNewline.replacement(in: MarkdownSourceMap.parse(text), sourceOffset: offset)
    }

    func testProseGetsAParagraphBreakAndLineBasedBlocksKeepASingleNewline() {
        XCTAssertEqual(replacement("Hello world", at: 5), "\n\n")
        XCTAssertEqual(replacement("Hello world", at: 11), "\n\n")
        XCTAssertEqual(replacement("# Title", at: 7), "\n\n")
        XCTAssertEqual(replacement("", at: 0), "\n\n")
        XCTAssertEqual(replacement("para\n\nnext", at: 5), "\n\n")
        XCTAssertEqual(replacement("- item", at: 6), "\n")
        XCTAssertEqual(replacement("- item\n\n  second para", at: 14), "\n")
        XCTAssertEqual(replacement("> quote", at: 4), "\n")
        XCTAssertEqual(replacement("```\ncode\n```", at: 6), "\n")
        XCTAssertEqual(replacement("    indented", at: 8), "\n")
        XCTAssertEqual(replacement("| a |\n|---|\n| 1 |", at: 2), "\n")
        XCTAssertEqual(replacement("---\ntitle: x\n---\nbody", at: 6), "\n")
        XCTAssertEqual(replacement("---\ntitle: x\n---\nbody", at: 20), "\n\n")
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
            "# Title\nSome **bold** and *em* text\n• item\ncode\n"
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

    func testAnEditTouchingAListMarkerIsRefused() throws {
        let host = try makeHost(text: "- item\n- two")
        XCTAssertEqual(host.reader.string, "• item\n• two")
        let marker = try host.readerRange(of: "• item")
        host.reader.setSelectedRange(marker)
        host.type("x")
        XCTAssertEqual(host.document.rawText, "- item\n- two")
        XCTAssertEqual(host.reader.string, "• item\n• two")
        XCTAssertEqual(host.coordinator.refusedEditCount, 1)

        host.placeCaret(at: marker.location + 2)
        host.reader.deleteBackward(nil)
        XCTAssertEqual(host.document.rawText, "- item\n- two")
        XCTAssertEqual(host.coordinator.refusedEditCount, 2)

        host.type("x")
        XCTAssertEqual(host.document.rawText, "- xitem\n- two")
        XCTAssertEqual(host.coordinator.refusedEditCount, 2)
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
        XCTAssertEqual(host.reader.string, "co\nde\n")
        XCTAssertEqual(host.reader.selectedRange(), NSRange(location: 3, length: 0))
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
