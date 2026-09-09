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
        XCTAssertTrue(rendered.contains("———"))
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
        XCTAssertNotNil(presentation.attributedString.attribute(.backgroundColor, at: codeLocation, effectiveRange: nil))

        let linkRange = try XCTUnwrap(rendered.range(of: "link"))
        XCTAssertNotNil(
            presentation.attributedString.attribute(
                .link,
                at: NSRange(linkRange, in: rendered).location,
                effectiveRange: nil
            )
        )
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
}
