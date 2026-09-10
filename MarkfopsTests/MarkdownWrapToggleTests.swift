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

    func testWrapMapsOffsetsBeforeInsideAndAfterTheRange() {
        let text = "Some bold text"
        let result = edit(text, select: "bold", prefix: "**", suffix: "**")
        // "Some " stays, "bold" shifts past the prefix, " text" past both delimiters.
        XCTAssertEqual((0..<5).map { result.newOffset(forOldOffset: $0) }, [0, 1, 2, 3, 4])
        XCTAssertEqual((5..<9).map { result.newOffset(forOldOffset: $0) }, [7, 8, 9, 10])
        XCTAssertEqual((9..<14).map { result.newOffset(forOldOffset: $0) }, [13, 14, 15, 16, 17])
        XCTAssertEqual(result.kept, [.init(old: NSRange(location: 5, length: 4), newLocation: 7)])

        let collapsed = edit("Hello world", select: "", prefix: "*", suffix: "*")
        XCTAssertEqual(collapsed.kept, [])
        XCTAssertEqual(collapsed.newOffset(forOldOffset: 0), 2)
    }

    func testUnwrapMapsTheContentAndDropsTheDelimiters() {
        let text = "Some **bold** text"
        let result = edit(text, select: "bold", prefix: "**", suffix: "**")
        XCTAssertEqual((0..<5).map { result.newOffset(forOldOffset: $0) }, [0, 1, 2, 3, 4])
        XCTAssertEqual([5, 6, 11, 12].map { result.newOffset(forOldOffset: $0) }, [nil, nil, nil, nil])
        XCTAssertEqual((7..<11).map { result.newOffset(forOldOffset: $0) }, [5, 6, 7, 8])
        XCTAssertEqual((13..<18).map { result.newOffset(forOldOffset: $0) }, [9, 10, 11, 12, 13])
        XCTAssertEqual(result.kept, [.init(old: NSRange(location: 7, length: 4), newLocation: 5)])

        // Every surviving character lands on its own new offset.
        let survivors = (0..<18).compactMap { result.newOffset(forOldOffset: $0) }
        XCTAssertEqual(Set(survivors).count, survivors.count)
        XCTAssertEqual(survivors.count, 14)
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
