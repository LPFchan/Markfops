import AppKit
import XCTest
@testable import Markfops

final class MarkdownWrapToggleTests: XCTestCase {
    private func edit(_ text: String, select fragment: String, prefix: String, suffix: String) -> MarkdownWrapToggle.Edit {
        let source = text as NSString
        let selection = fragment.isEmpty
            ? NSRange(location: 0, length: 0)
            : source.range(of: fragment)
        XCTAssertNotEqual(selection.location, NSNotFound, "missing \(fragment)")
        return MarkdownWrapToggle.edit(
            in: source,
            sourceMap: MarkdownSourceMap.parse(text),
            selection: selection,
            prefix: prefix,
            suffix: suffix
        )
    }

    private func apply(_ edit: MarkdownWrapToggle.Edit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testPlainSelectionWrapsAndSelectsTheContent() {
        let text = "Some bold text"
        let result = edit(text, select: "bold", prefix: "**", suffix: "**")
        XCTAssertEqual(apply(result, to: text), "Some **bold** text")
        XCTAssertEqual(result.selection, NSRange(location: 7, length: 4))
    }

    func testSelectionInsideBoldUnwrapsTheWholeConstruct() {
        let text = "Some **bold** text"
        let result = edit(text, select: "bold", prefix: "**", suffix: "**")
        XCTAssertEqual(apply(result, to: text), "Some bold text")
        XCTAssertEqual(result.selection, (("Some bold text") as NSString).range(of: "bold"))
    }

    func testSelectionIncludingDelimitersUnwraps() {
        let text = "Some **bold** text"
        let result = edit(text, select: "**bold**", prefix: "**", suffix: "**")
        XCTAssertEqual(apply(result, to: text), "Some bold text")
        XCTAssertEqual(result.selection, NSRange(location: 5, length: 4))
    }

    func testCollapsedCaretInsideBoldUnwrapsAndKeepsItsPlace() {
        let text = "Some **bold** text"
        let source = text as NSString
        let caret = NSRange(location: source.range(of: "ld").location, length: 0)
        let result = MarkdownWrapToggle.edit(
            in: source,
            sourceMap: MarkdownSourceMap.parse(text),
            selection: caret,
            prefix: "**",
            suffix: "**"
        )
        XCTAssertEqual(apply(result, to: text), "Some bold text")
        XCTAssertEqual(result.selection, NSRange(location: 7, length: 0))
    }

    func testItalicInsideBoldOnlyRemovesTheItalic() {
        let text = "**a *b* c**"
        let result = edit(text, select: "b", prefix: "*", suffix: "*")
        XCTAssertEqual(apply(result, to: text), "**a b c**")
        XCTAssertEqual(result.selection, NSRange(location: 4, length: 1))

        let bold = edit(text, select: "b", prefix: "**", suffix: "**")
        XCTAssertEqual(apply(bold, to: text), "a *b* c")
    }

    func testSelectionReachingOutsideTheConstructWrapsInstead() {
        let text = "Some **bold** text"
        let result = edit(text, select: "bold** text", prefix: "**", suffix: "**")
        XCTAssertEqual(apply(result, to: text), "Some ****bold** text**")
    }

    func testCodeSpanAndStrikethroughToggle() {
        let code = "run `setup` now"
        XCTAssertEqual(apply(edit(code, select: "setup", prefix: "`", suffix: "`"), to: code), "run setup now")
        let struck = "is ~~gone~~ now"
        XCTAssertEqual(apply(edit(struck, select: "gone", prefix: "~~", suffix: "~~"), to: struck), "is gone now")
        let plain = "is gone now"
        XCTAssertEqual(apply(edit(plain, select: "gone", prefix: "~~", suffix: "~~"), to: plain), "is ~~gone~~ now")
    }

    func testEditorCommandBTwiceRoundTrips() {
        let document = Document(rawText: "Some bold text")
        let textView = MarkdownNSTextView(textStorage: document.textStorage)
        textView.setSelectedRange(NSRange(location: 5, length: 4))
        textView.wrapSelection(prefix: "**", suffix: "**")
        XCTAssertEqual(textView.string, "Some **bold** text")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 4))
        textView.wrapSelection(prefix: "**", suffix: "**")
        XCTAssertEqual(textView.string, "Some bold text")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 4))
    }
}
