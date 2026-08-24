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

    private func makeTextView(text: String) -> (MarkdownNSTextView, MarkdownSyntaxHighlighter) {
        let textView = MarkdownNSTextView()
        let highlighter = MarkdownSyntaxHighlighter()
        textView.textStorage?.delegate = highlighter
        textView.string = text
        highlighter.updateConfiguration(.default)
        if let storage = textView.textStorage {
            highlighter.highlightAll(in: storage)
        }
        return (textView, highlighter)
    }
}
