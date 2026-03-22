import XCTest
@testable import Markfops

final class HeadingParserTests: XCTestCase {

    func testFirstH1Title() {
        let text = "# Hello World\n\nSome text\n\n## Section"
        XCTAssertEqual(HeadingParser.firstH1Title(in: text), "Hello World")
    }

    func testFirstH1TitleIgnoresH2() {
        let text = "## Not H1\n\n# Actual H1"
        XCTAssertEqual(HeadingParser.firstH1Title(in: text), "Actual H1")
    }

    func testFirstH1LetterUppercase() {
        let text = "# my document"
        XCTAssertEqual(HeadingParser.firstH1Letter(in: text), "M")
    }

    func testParseHeadings() {
        let text = """
        # Title
        Some text
        ## Section One
        ### Subsection
        ## Section Two
        """
        let headings = HeadingParser.parseHeadings(in: text)
        XCTAssertEqual(headings.count, 4)
        XCTAssertEqual(headings[0].level, 1)
        XCTAssertEqual(headings[0].title, "Title")
        XCTAssertEqual(headings[1].level, 2)
        XCTAssertEqual(headings[1].title, "Section One")
        XCTAssertEqual(headings[2].level, 3)
        XCTAssertEqual(headings[2].title, "Subsection")
    }

    func testEmptyDocument() {
        XCTAssertNil(HeadingParser.firstH1Title(in: ""))
        XCTAssertNil(HeadingParser.firstH1Letter(in: ""))
        XCTAssertTrue(HeadingParser.parseHeadings(in: "").isEmpty)
    }

    func testHeadingLineNumbers() {
        let text = "Intro\n# Title\nBody\n## Sub"
        let headings = HeadingParser.parseHeadings(in: text)
        XCTAssertEqual(headings[0].lineNumber, 1)
        XCTAssertEqual(headings[1].lineNumber, 3)
    }
}
