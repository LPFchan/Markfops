import XCTest
@testable import Markfops

final class MarkdownRendererTests: XCTestCase {

    func testBasicParagraph() {
        let html = MarkdownRenderer.renderHTML(from: "Hello, world!")
        XCTAssertTrue(html.contains("<p>"))
        XCTAssertTrue(html.contains("Hello, world!"))
    }

    func testHeading() {
        let html = MarkdownRenderer.renderHTML(from: "# Title")
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("Title"))
    }

    func testTable() {
        let text = """
        | Col A | Col B |
        |-------|-------|
        | 1     | 2     |
        """
        let html = MarkdownRenderer.renderHTML(from: text)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>"))
        XCTAssertTrue(html.contains("<td>"))
    }

    func testStrikethrough() {
        let html = MarkdownRenderer.renderHTML(from: "~~deleted~~")
        XCTAssertTrue(html.contains("<del>"))
    }

    func testEmptyInput() {
        let html = MarkdownRenderer.renderHTML(from: "")
        XCTAssertNotNil(html)
    }
}
