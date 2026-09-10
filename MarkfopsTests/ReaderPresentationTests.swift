import AppKit
import SwiftUI
import XCTest
@testable import Markfops

final class ReaderPresentationTests: XCTestCase {
    func testPresentationHidesSyntaxAndStylesSupportedConstructs() throws {
        let text = """
        # Heading

        A *word* **bold** `code` [link](https://example.com) ![alt](image.png).
        - item
        1. ordered
        - [ ] todo
        > quote
        ```swift
        let value = 1
        ```
        ---
        """
        let presentation = ReaderPresentation.build(
            text: text,
            sourceMap: MarkdownSourceMap.parse(text)
        )
        let rendered = presentation.attributedString.string

        XCTAssertTrue(rendered.contains("Heading"))
        XCTAssertTrue(rendered.contains("• item"))
        XCTAssertTrue(rendered.contains("1. ordered"))
        XCTAssertTrue(rendered.contains("☐ todo"))
        XCTAssertTrue(rendered.contains("quote"))
        XCTAssertTrue(rendered.contains("let value = 1"))
        XCTAssertTrue(rendered.contains("\u{200B}"))
        XCTAssertFalse(rendered.contains("#"))
        XCTAssertFalse(rendered.contains("*"))
        XCTAssertFalse(rendered.contains("`"))
        XCTAssertFalse(rendered.contains("["))
        XCTAssertFalse(rendered.contains("]"))
        XCTAssertFalse(rendered.contains("("))
        XCTAssertFalse(rendered.contains(")"))

        let headingRange = try XCTUnwrap(rendered.range(of: "Heading"))
        let headingNSRange = NSRange(headingRange, in: rendered)
        let headingFont = try XCTUnwrap(
            presentation.attributedString.attribute(.font, at: headingNSRange.location, effectiveRange: nil)
                as? NSFont
        )
        XCTAssertEqual(headingFont.pointSize, 32, accuracy: 0.1)

        let bodyRange = try XCTUnwrap(rendered.range(of: "word"))
        let bodyFont = try XCTUnwrap(
            presentation.attributedString.attribute(.font, at: NSRange(bodyRange, in: rendered).location, effectiveRange: nil)
                as? NSFont
        )
        XCTAssertTrue(bodyFont.fontDescriptor.symbolicTraits.contains(.italic))

        let strongRange = try XCTUnwrap(rendered.range(of: "bold"))
        let strongFont = try XCTUnwrap(
            presentation.attributedString.attribute(.font, at: NSRange(strongRange, in: rendered).location, effectiveRange: nil)
                as? NSFont
        )
        XCTAssertGreaterThan(NSFontManager.shared.weight(of: strongFont), 5)

        let codeRange = try XCTUnwrap(rendered.range(of: "code"))
        let codeLocation = NSRange(codeRange, in: rendered).location
        let codeFont = try XCTUnwrap(
            presentation.attributedString.attribute(.font, at: codeLocation, effectiveRange: nil)
                as? NSFont
        )
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertNotNil(
            presentation.attributedString.attribute(
                .readerCodeSpan,
                at: codeLocation,
                effectiveRange: nil
            )
        )
        XCTAssertNil(
            presentation.attributedString.attribute(
                .backgroundColor,
                at: codeLocation,
                effectiveRange: nil
            )
        )

        let linkRange = try XCTUnwrap(rendered.range(of: "link"))
        XCTAssertNotNil(
            presentation.attributedString.attribute(
                .link,
                at: NSRange(linkRange, in: rendered).location,
                effectiveRange: nil
            )
        )
    }

    func testBlockSpacingAndNestedListIndentsFollowReaderRhythm() throws {
        let text = """
        - root
          - child
            - grandchild

        ```swift
        one
        two
        ```
        """
        let presentation = ReaderPresentation.build(
            text: text,
            sourceMap: MarkdownSourceMap.parse(text)
        )
        let rendered = presentation.attributedString.string

        let rootLocation = NSRange(rendered.range(of: "root")!, in: rendered).location
        let childLocation = NSRange(rendered.range(of: "child")!, in: rendered).location
        let grandchildLocation = NSRange(
            rendered.range(of: "grandchild")!,
            in: rendered
        ).location
        let rootStyle = try XCTUnwrap(
            presentation.attributedString.attribute(
                .paragraphStyle,
                at: rootLocation,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        let childStyle = try XCTUnwrap(
            presentation.attributedString.attribute(
                .paragraphStyle,
                at: childLocation,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        let grandchildStyle = try XCTUnwrap(
            presentation.attributedString.attribute(
                .paragraphStyle,
                at: grandchildLocation,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        XCTAssertEqual(childStyle.headIndent - rootStyle.headIndent, 32, accuracy: 0.1)
        XCTAssertEqual(
            grandchildStyle.headIndent - childStyle.headIndent,
            32,
            accuracy: 0.1
        )

        let firstCodeLocation = NSRange(rendered.range(of: "one")!, in: rendered).location
        let secondCodeLocation = NSRange(rendered.range(of: "two")!, in: rendered).location
        let firstCodeStyle = try XCTUnwrap(
            presentation.attributedString.attribute(
                .paragraphStyle,
                at: firstCodeLocation,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        let secondCodeStyle = try XCTUnwrap(
            presentation.attributedString.attribute(
                .paragraphStyle,
                at: secondCodeLocation,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        XCTAssertEqual(firstCodeStyle.paragraphSpacing, 0, accuracy: 0.1)
        XCTAssertEqual(secondCodeStyle.paragraphSpacingBefore, 0, accuracy: 0.1)
        XCTAssertGreaterThan(firstCodeStyle.paragraphSpacingBefore, 0)
        XCTAssertGreaterThan(secondCodeStyle.paragraphSpacing, 0)

        let tableText = "| a | b |\n|---|---|\n| 1 | 2 |"
        let tablePresentation = ReaderPresentation.build(
            text: tableText,
            sourceMap: MarkdownSourceMap.parse(tableText)
        )
        let tableLocation = NSRange(tablePresentation.attributedString.string.range(of: "| a")!, in: tablePresentation.attributedString.string).location
        let tableStyle = try XCTUnwrap(
            tablePresentation.attributedString.attribute(
                .paragraphStyle,
                at: tableLocation,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        XCTAssertEqual(tableStyle.paragraphSpacing, 0, accuracy: 0.1)
        XCTAssertGreaterThan(tableStyle.paragraphSpacingBefore, 0)

        let htmlText = "<div>\nraw\n</div>"
        let htmlPresentation = ReaderPresentation.build(
            text: htmlText,
            sourceMap: MarkdownSourceMap.parse(htmlText)
        )
        XCTAssertEqual(htmlPresentation.attributedString.string, htmlText)
        let htmlMiddleLocation = NSRange(
            htmlPresentation.attributedString.string.range(of: "raw")!,
            in: htmlPresentation.attributedString.string
        ).location
        let htmlMiddleStyle = try XCTUnwrap(
            htmlPresentation.attributedString.attribute(
                .paragraphStyle,
                at: htmlMiddleLocation,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        XCTAssertEqual(htmlMiddleStyle.paragraphSpacingBefore, 0, accuracy: 0.1)
        XCTAssertEqual(htmlMiddleStyle.paragraphSpacing, 0, accuracy: 0.1)
    }

    func testFrontMatterRendersRowsWithMonospacedKeys() throws {
        let text = """
        ---
        title: Reader check
        summary: |
          first line
          second line
        ---
        # Heading
        """
        let presentation = ReaderPresentation.build(
            text: text,
            sourceMap: MarkdownSourceMap.parse(text)
        )
        let rendered = presentation.attributedString.string

        XCTAssertTrue(rendered.contains("title\tReader check"))
        XCTAssertTrue(rendered.contains("summary\t|\n\t  first line\n\t  second line"))
        XCTAssertFalse(rendered.contains("---"))

        let titleLocation = NSRange(rendered.range(of: "title")!, in: rendered).location
        let titleFont = try XCTUnwrap(
            presentation.attributedString.attribute(
                .font,
                at: titleLocation,
                effectiveRange: nil
            ) as? NSFont
        )
        XCTAssertTrue(titleFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertEqual(
            presentation.attributedString.attribute(
                .readerFrontMatter,
                at: titleLocation,
                effectiveRange: nil
            ) as? Bool,
            true
        )
    }

    func testLocalImagesBecomeAttachmentsAndMissingImagesStayAltText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkfopsReaderImages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let imageData = try XCTUnwrap(
            bitmap.representation(using: .png, properties: [:])
        )
        try imageData.write(to: directory.appendingPathComponent("local.png"))

        let localText = "![local alt](local.png)"
        let localPresentation = ReaderPresentation.build(
            text: localText,
            sourceMap: MarkdownSourceMap.parse(localText),
            baseURL: directory
        )
        XCTAssertTrue(localPresentation.attributedString.string.hasPrefix("\u{FFFC}"))
        XCTAssertTrue(
            localPresentation.attributedString.attribute(
                .attachment,
                at: 0,
                effectiveRange: nil
            ) is NSTextAttachment
        )
        XCTAssertTrue(localPresentation.attributedString.string.contains("local alt"))

        let missingText = "![missing alt](missing.png)"
        let missingPresentation = ReaderPresentation.build(
            text: missingText,
            sourceMap: MarkdownSourceMap.parse(missingText),
            baseURL: directory
        )
        XCTAssertFalse(missingPresentation.attributedString.string.contains("\u{FFFC}"))
        XCTAssertTrue(missingPresentation.attributedString.string.contains("missing alt"))
    }

    func testKoreanAndEmojiKeepFontsAfterAttributeFixing() {
        let text = "# 안녕 🦊\n한국어 설명과 emoji 🚀"
        let presentation = ReaderPresentation.build(
            text: text,
            sourceMap: MarkdownSourceMap.parse(text)
        )
        let fixed = presentation.attributedString.mutableCopy() as! NSMutableAttributedString
        fixed.fixAttributes(in: NSRange(location: 0, length: fixed.length))

        var fontCount = 0
        fixed.enumerateAttribute(.font, in: NSRange(location: 0, length: fixed.length)) { value, _, _ in
            XCTAssertNotNil(value as? NSFont)
            fontCount += 1
        }
        XCTAssertGreaterThan(fontCount, 0)
        XCTAssertTrue(fixed.string.contains("안녕 🦊"))
        XCTAssertTrue(fixed.string.contains("한국어 설명과 emoji 🚀"))
    }

    func testOffsetMapRoundTripsContentAndMapsHiddenSyntaxForward() throws {
        let text = "# Heading\nA *word* and `code`\n"
        let sourceMap = MarkdownSourceMap.parse(text)
        let presentation = ReaderPresentation.build(text: text, sourceMap: sourceMap)
        let rendered = presentation.attributedString.string as NSString

        for run in sourceMap.runs(in: NSRange(location: 0, length: (text as NSString).length))
        where run.role == .content && run.kind != .softBreak && run.kind != .lineBreak {
            for sourceOffset in run.range.location..<NSMaxRange(run.range) {
                let readerOffset = presentation.offsetMap.readerOffset(forSourceOffset: sourceOffset)
                XCTAssertLessThan(readerOffset, rendered.length)
                XCTAssertEqual(
                    rendered.character(at: readerOffset),
                    (text as NSString).character(at: sourceOffset)
                )
            }
        }

        let headingSyntax = try XCTUnwrap((text as NSString).range(of: "# ").location as Int?)
        let headingText = (text as NSString).range(of: "Heading")
        XCTAssertEqual(
            presentation.offsetMap.readerOffset(forSourceOffset: headingSyntax),
            presentation.offsetMap.readerOffset(forSourceOffset: headingText.location)
        )

        let headingReaderRange = try XCTUnwrap(presentation.offsetMap.readerRange(forSourceLine: 0))
        XCTAssertEqual(rendered.substring(with: headingReaderRange), "Heading")
    }

    func testReaderViewScrollsToAndReportsALateSourceLine() throws {
        let lines = (0..<180).map { index in
            index == 160 ? "## Target" : "Line \(index)"
        }
        let text = lines.joined(separator: "\n")
        let document = Document(rawText: text)
        document.headings = MarkdownSourceMap.parse(text).headings
        let bridge = ReaderBridge()
        let hostingView = NSHostingView(rootView: ReaderView(
            document: document,
            theme: .default,
            themeKey: "light",
            readerBridge: bridge,
            isActive: true
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settleReader(hostingView)

        XCTAssertTrue(bridge.scrollToSourceLineCentered(160))
        settleReader(hostingView)
        XCTAssertEqual(bridge.currentSourceLineAtViewportCenter(), 160)
    }

    func testEditModeHasExactlyTwoCasesAndOldReaderSnapshotsFallBackToEdit() {
        XCTAssertEqual(EditMode.allCases, [.edit, .preview])
        XCTAssertNil(EditMode(rawValue: "reader"))
        XCTAssertEqual(EditMode(rawValue: "reader") ?? .edit, .edit)
    }

    private func settleReader(_ view: NSView) {
        for _ in 0..<8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Empty lines carry the block gap

    private let em = ReaderTheme.default.bodyFontSize

    private func build(_ text: String, reveal: NSRange? = nil) -> ReaderPresentation {
        ReaderPresentation.build(
            text: text,
            sourceMap: MarkdownSourceMap.parse(text),
            revealedSourceRange: reveal
        )
    }

    /// The paragraph style at the first character of `fragment` in the reader.
    private func style(of fragment: String, in presentation: ReaderPresentation) throws -> NSParagraphStyle {
        let rendered = presentation.attributedString.string as NSString
        let range = rendered.range(of: fragment)
        XCTAssertNotEqual(range.location, NSNotFound, "missing \(fragment)")
        return try XCTUnwrap(
            presentation.attributedString.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                as? NSParagraphStyle
        )
    }

    /// The style of the `index`-th empty line (lone newline) in the reader.
    private func blankStyle(_ index: Int, in presentation: ReaderPresentation) throws -> NSParagraphStyle {
        let rendered = presentation.attributedString.string as NSString
        var found = 0
        for offset in 0..<rendered.length where rendered.character(at: offset) == 0x0A
            && (offset == 0 || rendered.character(at: offset - 1) == 0x0A) {
            if found == index {
                return try XCTUnwrap(
                    presentation.attributedString.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
                        as? NSParagraphStyle
                )
            }
            found += 1
        }
        throw XCTSkip("empty line \(index) not found")
    }

    func testEmptyLineBetweenParagraphsTakesBothSpacingsAndZeroesThemOnTheNeighbours() throws {
        let presentation = build("First paragraph.\n\nSecond paragraph.\n")
        XCTAssertEqual(presentation.attributedString.string, "First paragraph.\n\nSecond paragraph.\n")

        let blank = try blankStyle(0, in: presentation)
        XCTAssertEqual(blank.minimumLineHeight, em * 1.5, accuracy: 0.01)
        XCTAssertEqual(blank.maximumLineHeight, em * 1.5, accuracy: 0.01)
        XCTAssertEqual(blank.paragraphSpacing, 0)
        XCTAssertEqual(blank.paragraphSpacingBefore, 0)

        let first = try style(of: "First", in: presentation)
        XCTAssertEqual(first.paragraphSpacing, 0, "the facing spacing moved onto the empty line")
        XCTAssertEqual(first.paragraphSpacingBefore, em * 0.75, accuracy: 0.01, "the far side is untouched")
        XCTAssertEqual(first.maximumLineHeight, 0)
        let second = try style(of: "Second", in: presentation)
        XCTAssertEqual(second.paragraphSpacingBefore, 0)
        XCTAssertEqual(second.paragraphSpacing, em * 0.75, accuracy: 0.01)
        // The whole neighbour paragraph changes, including its own newline.
        let firstNewline = try style(of: "\n\nSecond", in: presentation)
        XCTAssertEqual(firstNewline.paragraphSpacing, 0)
    }

    func testEmptyLineHeightFollowsTheNeighboursKinds() throws {
        let beforeHeading = build("Paragraph.\n\n# Heading\n")
        XCTAssertEqual(try blankStyle(0, in: beforeHeading).maximumLineHeight, em * (0.75 + 1.5), accuracy: 0.01)
        XCTAssertEqual(try style(of: "Heading", in: beforeHeading).paragraphSpacingBefore, 0)
        XCTAssertEqual(try style(of: "Heading", in: beforeHeading).paragraphSpacing, em * 0.5, accuracy: 0.01)

        let afterQuote = build("> quote\n\nParagraph.\n")
        XCTAssertEqual(try blankStyle(0, in: afterQuote).maximumLineHeight, em * (0.25 + 0.75), accuracy: 0.01)
        XCTAssertEqual(try style(of: "quote", in: afterQuote).paragraphSpacing, 0)
        XCTAssertEqual(try style(of: "Paragraph", in: afterQuote).paragraphSpacingBefore, 0)

        let betweenItems = build("- one\n\n- two\n")
        XCTAssertEqual(try blankStyle(0, in: betweenItems).maximumLineHeight, em, accuracy: 0.01, "clamped to the body size")
        XCTAssertEqual(try style(of: "one", in: betweenItems).paragraphSpacing, 0)
        XCTAssertEqual(try style(of: "two", in: betweenItems).paragraphSpacingBefore, 0)

        let twoEmpties = build("First paragraph.\n\n\nSecond paragraph.\n")
        XCTAssertEqual(try blankStyle(0, in: twoEmpties).maximumLineHeight, em, accuracy: 0.01, "0.75 em clamped up")
        XCTAssertEqual(try blankStyle(1, in: twoEmpties).maximumLineHeight, em, accuracy: 0.01)
        XCTAssertEqual(try style(of: "First", in: twoEmpties).paragraphSpacing, 0)
        XCTAssertEqual(try style(of: "Second", in: twoEmpties).paragraphSpacingBefore, 0)

        let atTheEdges = build("\nOnly.\n\n")
        XCTAssertEqual(try blankStyle(0, in: atTheEdges).maximumLineHeight, em, accuracy: 0.01)
        XCTAssertEqual(try blankStyle(1, in: atTheEdges).maximumLineHeight, em, accuracy: 0.01)
        XCTAssertEqual(try style(of: "Only", in: atTheEdges).paragraphSpacingBefore, 0)
        XCTAssertEqual(try style(of: "Only", in: atTheEdges).paragraphSpacing, 0)
    }

    func testEmptyLineNextToACodePanelLeavesThePanelSpacingOnTheBlock() throws {
        // The panel is drawn over the block's own 1.25 em edge spacing, so an
        // empty line next to it takes only the paragraph's share and stays
        // outside the panel.
        let presentation = build("Paragraph.\n\n```\ncode\n```\n\nAfter.\n")
        XCTAssertEqual(presentation.attributedString.string, "Paragraph.\n\ncode\n\nAfter.\n")
        XCTAssertEqual(try blankStyle(0, in: presentation).maximumLineHeight, em, accuracy: 0.01)
        XCTAssertEqual(try blankStyle(1, in: presentation).maximumLineHeight, em, accuracy: 0.01)
        XCTAssertEqual(try style(of: "Paragraph", in: presentation).paragraphSpacing, 0)
        let code = try style(of: "code", in: presentation)
        XCTAssertEqual(code.paragraphSpacingBefore, em * 1.25, accuracy: 0.01)
        XCTAssertEqual(code.paragraphSpacing, em * 1.25, accuracy: 0.01)
        XCTAssertEqual(try style(of: "After", in: presentation).paragraphSpacingBefore, 0)
    }

    func testEmptyLinesInsideCodeAndListsAreNotTouched() throws {
        let presentation = build("```\na\n\nb\n```\n- item\n\n  more\n")
        let rendered = presentation.attributedString.string as NSString
        let codeBlank = rendered.range(of: "a\n\nb").location + 2
        let codeStyle = try XCTUnwrap(
            presentation.attributedString.attribute(.paragraphStyle, at: codeBlank, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertEqual(codeStyle.maximumLineHeight, 0, "a blank code line keeps the code style")
        XCTAssertEqual(codeStyle.lineHeightMultiple, 1.6, accuracy: 0.01)
        let listBlank = rendered.range(of: "item\n\n").location + 5
        let listStyle = try XCTUnwrap(
            presentation.attributedString.attribute(.paragraphStyle, at: listBlank, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertEqual(listStyle.maximumLineHeight, 0, "a blank line inside a list item keeps the list style")
    }

    // MARK: - Fences reveal

    func testRevealedFencesStandOnTheirOwnLinesInsideThePanelAndTakeTheEdgeSpacing() throws {
        let text = "Intro.\n\n```swift\nlet x = 1\nlet y = 2\n```\n\nAfter.\n"
        let source = text as NSString
        let block = source.range(of: "```swift\nlet x = 1\nlet y = 2\n```")
        XCTAssertEqual(ReaderReveal.range(in: MarkdownSourceMap.parse(text), sourceCursor: block.location + 12), block)
        let hidden = build(text)
        XCTAssertEqual(hidden.attributedString.string, "Intro.\n\nlet x = 1\nlet y = 2\n\nAfter.\n")

        let revealed = build(text, reveal: block)
        XCTAssertEqual(revealed.attributedString.string, "Intro.\n\n```swift\nlet x = 1\nlet y = 2\n```\n\nAfter.\n")

        let opening = try style(of: "```swift", in: revealed)
        XCTAssertEqual(opening.paragraphSpacingBefore, em * 1.25, accuracy: 0.01)
        XCTAssertEqual(opening.paragraphSpacing, 0)
        let firstLine = try style(of: "let x", in: revealed)
        XCTAssertEqual(firstLine.paragraphSpacingBefore, 0)
        XCTAssertEqual(firstLine.paragraphSpacing, 0)
        let lastLine = try style(of: "let y", in: revealed)
        XCTAssertEqual(lastLine.paragraphSpacing, 0)
        let closing = try style(of: "```\n\nAfter", in: revealed)
        XCTAssertEqual(closing.paragraphSpacingBefore, 0)
        XCTAssertEqual(closing.paragraphSpacing, em * 1.25, accuracy: 0.01)

        let rendered = revealed.attributedString.string as NSString
        let blockValue = revealed.attributedString.attribute(
            .readerCodeBlock, at: rendered.range(of: "let x").location, effectiveRange: nil
        ) as? NSValue
        XCTAssertNotNil(blockValue)
        for fragment in ["```swift", "```\n\nAfter"] {
            let location = rendered.range(of: fragment).location
            XCTAssertEqual(
                revealed.attributedString.attribute(.readerCodeBlock, at: location, effectiveRange: nil) as? NSValue,
                blockValue,
                "\(fragment) is inside the panel"
            )
            XCTAssertEqual(
                revealed.attributedString.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor,
                ReaderTheme.default.secondaryColor
            )
            let font = try XCTUnwrap(
                revealed.attributedString.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            )
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        }
        XCTAssertEqual(
            revealed.attributedString.attribute(.foregroundColor, at: rendered.range(of: "let x").location, effectiveRange: nil) as? NSColor,
            ReaderTheme.default.bodyColor
        )

        // The fences map one-to-one and the content keeps its offsets.
        XCTAssertEqual(
            revealed.offsetMap.sourceRange(forReaderRange: rendered.range(of: "```swift")),
            source.range(of: "```swift")
        )
        XCTAssertEqual(
            revealed.offsetMap.sourceRange(forReaderRange: rendered.range(of: "let y = 2")),
            source.range(of: "let y = 2")
        )
        XCTAssertEqual(
            revealed.offsetMap.sourceInsertionOffset(forReaderOffset: rendered.range(of: "```swift").location),
            source.range(of: "```swift").location
        )

        // The empty lines around the block are unchanged by the reveal.
        XCTAssertEqual(try blankStyle(0, in: revealed).maximumLineHeight, try blankStyle(0, in: hidden).maximumLineHeight)
        XCTAssertEqual(try blankStyle(1, in: revealed).maximumLineHeight, try blankStyle(1, in: hidden).maximumLineHeight)
    }

    func testRevealedUnclosedFenceLeavesTheEdgeSpacingOnTheLastContentLine() throws {
        let text = "```\ncode\nmore"
        let revealed = build(text, reveal: NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(revealed.attributedString.string, "```\ncode\nmore")
        XCTAssertEqual(try style(of: "```", in: revealed).paragraphSpacingBefore, em * 1.25, accuracy: 0.01)
        XCTAssertEqual(try style(of: "code", in: revealed).paragraphSpacingBefore, 0)
        XCTAssertEqual(try style(of: "more", in: revealed).paragraphSpacing, em * 1.25, accuracy: 0.01)
    }

    func testRevealedQuoteShowsItsMarkersInTheQuoteStyle() throws {
        let text = "> one\n> two\n"
        let revealed = build(text, reveal: NSRange(location: 0, length: 11))
        XCTAssertEqual(revealed.attributedString.string, "> one\n> two\n")
        let marker = revealed.attributedString
        XCTAssertEqual(marker.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, ReaderTheme.default.secondaryColor)
        XCTAssertEqual(marker.attribute(.readerBlockQuote, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(try style(of: "> one", in: revealed).headIndent, em, accuracy: 0.01)
        XCTAssertEqual(revealed.offsetMap.sourceInsertionOffset(forReaderOffset: 0), 0, "the caret before a shown marker stays before it")
        XCTAssertEqual(revealed.offsetMap.sourceInsertionOffset(forReaderOffset: 2), 2)
        XCTAssertEqual(build(text).offsetMap.sourceInsertionOffset(forReaderOffset: 0), 2, "hidden markers are skipped")
    }
}
