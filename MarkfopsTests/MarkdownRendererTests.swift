import XCTest
@testable import Markfops

final class MarkdownRendererTests: XCTestCase {

    func testBasicParagraph() {
        let html = MarkdownRenderer.renderHTML(from: "Hello, world!")
        XCTAssertTrue(containsOpeningTag("p", in: html))
        XCTAssertTrue(html.contains("Hello, world!"))
    }

    func testHeading() {
        let html = MarkdownRenderer.renderHTML(from: "# Title")
        XCTAssertTrue(containsOpeningTag("h1", in: html))
        XCTAssertTrue(html.contains("Title"))
    }

    func testTable() {
        let text = """
        | Col A | Col B |
        |-------|-------|
        | 1     | 2     |
        """
        let html = MarkdownRenderer.renderHTML(from: text)
        XCTAssertTrue(containsOpeningTag("table", in: html))
        XCTAssertTrue(containsOpeningTag("th", in: html))
        XCTAssertTrue(containsOpeningTag("td", in: html))
    }

    func testStrikethrough() {
        let html = MarkdownRenderer.renderHTML(from: "~~deleted~~")
        XCTAssertTrue(html.contains("<del>"))
    }

    func testEmptyInput() {
        let html = MarkdownRenderer.renderHTML(from: "")
        XCTAssertNotNil(html)
    }

    func testSourceLineAttributesPreserveUnicodeBlocks() {
        let markdown = "😀\n\n# Заголовок\n\n正文"
        let html = MarkdownRenderer.renderHTML(from: markdown)

        XCTAssertEqual(html.components(separatedBy: "data-markfops-source-line=\"0\"").count - 1, 1)
        XCTAssertEqual(html.components(separatedBy: "data-markfops-source-line=\"2\"").count - 1, 1)
        XCTAssertEqual(html.components(separatedBy: "data-markfops-source-line=\"4\"").count - 1, 1)
        XCTAssertTrue(html.contains("😀"))
        XCTAssertTrue(html.contains("正文"))
    }

    private func containsOpeningTag(_ tag: String, in html: String) -> Bool {
        html.range(of: "<\(tag)(?:\\s[^>]*)?>", options: .regularExpression) != nil
    }
}
