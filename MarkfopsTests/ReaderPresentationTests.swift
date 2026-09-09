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

    func testEmptySourceLinesCollapseBetweenBlocks() {
        let text = "First paragraph.\n\nSecond paragraph.\n\n\n# Heading\n"
        let presentation = ReaderPresentation.build(
            text: text,
            sourceMap: MarkdownSourceMap.parse(text),
            theme: .default,
            baseURL: nil
        )
        let rendered = presentation.attributedString
        let output = rendered.string as NSString

        // Every empty source line survives as a newline so line pairing holds.
        XCTAssertTrue(output.contains("First paragraph.\n\nSecond paragraph.\n\n\n"))

        let blankOffset = output.range(of: "\n\nSecond").location + 1
        let blank = rendered.attribute(.paragraphStyle, at: blankOffset, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(blank?.maximumLineHeight, ReaderTheme.default.bodyFontSize * 0.25)
        XCTAssertEqual(blank?.paragraphSpacing, 0)
        XCTAssertEqual(blank?.paragraphSpacingBefore, 0)

        let body = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(body?.maximumLineHeight, 0)
        XCTAssertGreaterThan(body?.paragraphSpacing ?? 0, 0)
    }
}
