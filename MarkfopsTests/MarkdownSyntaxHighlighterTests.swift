import AppKit
import XCTest
@testable import Markfops

final class MarkdownSyntaxHighlighterTests: XCTestCase {

    func testInitialHighlightingOwnsSyntaxAttributes() {
        let (textView, _) = makeTextView(text: "# Heading\nBody")
        let headingRange = NSRange(location: 0, length: ("# Heading" as NSString).length)

        XCTAssertTrue(
            (textView.textStorage?.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? NSColor)?.isEqual(NSColor.systemBlue) == true
        )
        XCTAssertTrue(
            (textView.textStorage?.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
        )
        XCTAssertNotNil(textView.textStorage?.attribute(.paragraphStyle, at: headingRange.location, effectiveRange: nil))
    }

    func testConfigurationApplicationDoesNotOverwriteSyntaxAttributes() {
        let (textView, highlighter) = makeTextView(text: "# Heading\nBody")
        let headingRange = NSRange(location: 0, length: ("# Heading" as NSString).length)
        let originalColor = textView.textStorage?.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? NSColor
        let originalFont = textView.textStorage?.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont

        var updated = EditorConfiguration.default
        updated.fontSize = 19
        updated.lineHeightMultiple = 1.7
        textView.configuration = updated

        XCTAssertTrue((textView.textStorage?.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? NSColor)?.isEqual(originalColor) == true)
        XCTAssertTrue((textView.textStorage?.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont)?.isEqual(originalFont) == true)
        XCTAssertEqual(
            (textView.textStorage?.attribute(.paragraphStyle, at: headingRange.location, effectiveRange: nil) as? NSParagraphStyle)?.lineHeightMultiple,
            1.4
        )

        XCTAssertTrue(highlighter.updateConfiguration(updated))
        if let storage = textView.textStorage {
            highlighter.highlightAll(in: storage)
        }
        XCTAssertEqual(
            (textView.textStorage?.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont)?.pointSize,
            19
        )
        XCTAssertEqual(
            (textView.textStorage?.attribute(.paragraphStyle, at: headingRange.location, effectiveRange: nil) as? NSParagraphStyle)?.lineHeightMultiple,
            1.7
        )
    }

    func testEditingReappliesSyntaxAttributesForChangedLine() {
        let (textView, _) = makeTextView(text: "Body")
        let range = NSRange(location: 0, length: ("Body" as NSString).length)
        textView.textStorage?.replaceCharacters(in: range, with: "**Body**")

        XCTAssertTrue(
            (textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.isEqual(EditorConfiguration.default.textColor) == true
        )
        XCTAssertTrue(
            (textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.isEqual(EditorConfiguration.default.font) == true
        )
        XCTAssertNotNil(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
    }

    func testUnchangedDisableEnableKeepsHighlightingValid() {
        let (_, highlighter) = makeTextView(text: "# Heading")

        XCTAssertFalse(highlighter.needsFullHighlight)
        highlighter.isEnabled = false
        highlighter.isEnabled = true

        XCTAssertFalse(highlighter.needsFullHighlight)
    }

    func testHiddenMutationBecomesStaleAndActivationClearsIt() {
        let (textView, highlighter) = makeTextView(text: "Body")
        highlighter.isEnabled = false
        textView.textStorage?.replaceCharacters(
            in: NSRange(location: 0, length: ("Body" as NSString).length),
            with: "# Heading"
        )

        XCTAssertTrue(highlighter.needsFullHighlight)
        highlighter.isEnabled = true
        highlighter.highlightAll(in: textView.textStorage!)

        XCTAssertFalse(highlighter.needsFullHighlight)
        XCTAssertTrue(
            (textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.isEqual(NSColor.systemBlue) == true
        )
    }

    func testDisabledHighlightingSkipsProgrammaticChanges() {
        let storage = NSTextStorage()
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.isEnabled = false
        storage.delegate = highlighter
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Heading")

        highlighter.highlightAll(in: storage)

        XCTAssertNil(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        XCTAssertTrue(highlighter.needsFullHighlight)
        highlighter.isEnabled = true
        highlighter.highlightAll(in: storage)
        XCTAssertFalse(highlighter.needsFullHighlight)
        XCTAssertTrue(
            (storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.isEqual(NSColor.systemBlue) == true
        )
    }

    func testHighlightingRepairsFallbackFontsForKoreanAndCJKText() {
        let text = "Latin 한글 日本語 中文"
        let (textView, _) = makeTextView(text: text)
        let storage = try! XCTUnwrap(textView.textStorage)

        for sample in ["한글", "日本語", "中文"] {
            let range = (text as NSString).range(of: sample)
            storage.enumerateAttribute(.font, in: range) { value, fontRange, _ in
                guard let font = value as? NSFont else {
                    return XCTFail("Missing font for \(sample) at \(fontRange)")
                }
                let run = (storage.string as NSString).substring(with: fontRange)
                XCTAssertTrue(fontCanRender(run, font: font), "\(font.fontName) cannot render \(run)")
            }
        }
    }

    func testMarkedTextIsNotHighlightedUntilCompositionFinishes() {
        let (textView, highlighter) = makeTextView(text: "")
        let storage = try! XCTUnwrap(textView.textStorage)

        textView.setMarkedText(
            "ㅎ",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        textView.setMarkedText(
            "하",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        textView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "한")
        XCTAssertFalse(highlighter.needsFullHighlight)
        XCTAssertTrue(highlighter.needsDeferredHighlight)

        textView.unmarkText()
        waitForMainQueue()

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertFalse(highlighter.needsFullHighlight)
        XCTAssertFalse(highlighter.needsDeferredHighlight)
        let font = try! XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(fontCanRender("한", font: font))
    }

    func testCommittingMarkedTextAutomaticallyFlushesDeferredHighlighting() {
        let (textView, highlighter) = makeTextView(text: "")
        let storage = try! XCTUnwrap(textView.textStorage)

        textView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertFalse(highlighter.needsFullHighlight)
        XCTAssertTrue(highlighter.needsDeferredHighlight)

        textView.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
        waitForMainQueue()

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "한")
        XCTAssertFalse(highlighter.needsFullHighlight)
        XCTAssertFalse(highlighter.needsDeferredHighlight)
        let font = try! XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(fontCanRender("한", font: font))
    }

    private func makeTextView(text: String) -> (MarkdownNSTextView, MarkdownSyntaxHighlighter) {
        let textView = MarkdownNSTextView()
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.textView = textView
        textView.syntaxHighlighter = highlighter
        textView.textStorage?.delegate = highlighter
        textView.string = text
        highlighter.updateConfiguration(.default)
        if let storage = textView.textStorage {
            highlighter.highlightAll(in: storage)
        }
        return (textView, highlighter)
    }

    private func fontCanRender(_ text: String, font: NSFont) -> Bool {
        var characters = Array(text.utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        return CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
    }

    private func waitForMainQueue() {
        let flushed = expectation(description: "main queue flushed")
        DispatchQueue.main.async {
            flushed.fulfill()
        }
        wait(for: [flushed], timeout: 1)
    }
}
