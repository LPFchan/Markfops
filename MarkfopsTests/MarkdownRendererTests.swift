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

    func testLeadingYAMLFrontMatterIsHiddenFromPreview() {
        let markdown = """
        ---
        name: fleet
        description: "Fleet topology"
        tags: [fleet, ssh]
        audience: fleet
        ---
        # Fleet

        Body
        """
        let html = MarkdownRenderer.renderHTML(from: markdown)

        XCTAssertFalse(html.contains("name: fleet"))
        XCTAssertFalse(html.contains("Fleet topology"))
        XCTAssertFalse(html.contains("audience: fleet"))
        XCTAssertTrue(html.contains("Fleet"))
        XCTAssertTrue(html.contains("Body"))
    }

    func testFrontMatterMaskPreservesBodySourceLines() {
        let markdown = "---\ntitle: Example\n---\n# Heading"
        let html = MarkdownRenderer.renderHTML(from: markdown)

        XCTAssertTrue(html.contains("data-markfops-source-line=\"3\""))
        XCTAssertTrue(html.contains("id=\"markfops-heading-3-1\""))
    }

    func testFrontMatterMayUseYAMLEndMarker() {
        let markdown = "---\ntitle: Example\n...\nVisible"
        let html = MarkdownRenderer.renderHTML(from: markdown)

        XCTAssertFalse(html.contains("title: Example"))
        XCTAssertTrue(html.contains("Visible"))
    }

    func testHorizontalRuleOutsideLeadingFrontMatterStillRenders() {
        let html = MarkdownRenderer.renderHTML(from: "Before\n\n---\n\nAfter")

        XCTAssertTrue(containsOpeningTag("hr", in: html))
        XCTAssertTrue(html.contains("Before"))
        XCTAssertTrue(html.contains("After"))
    }

    func testUnclosedFrontMatterDelimiterRendersAsMarkdown() {
        let html = MarkdownRenderer.renderHTML(from: "---\nname: visible")

        XCTAssertTrue(containsOpeningTag("hr", in: html))
        XCTAssertTrue(html.contains("name: visible"))
    }

    private func containsOpeningTag(_ tag: String, in html: String) -> Bool {
        html.range(of: "<\(tag)(?:\\s[^>]*)?>", options: .regularExpression) != nil
    }
}
