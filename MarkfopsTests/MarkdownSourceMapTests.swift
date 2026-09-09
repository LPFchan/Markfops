import AppKit
import XCTest
@testable import Markfops

final class MarkdownSourceMapTests: XCTestCase {
    func testInlineSourcePositionsConvertUTF8ColumnsToUTF16Ranges() throws {
        let text = "# 안녕 🦊 e\u{301}\n"
        let map = MarkdownSourceMap.parse(text)
        let titleRange = try XCTUnwrap(range(of: "안녕 🦊 e\u{301}", in: text))
        let titleSpan = try XCTUnwrap(map.span(at: titleRange.location))

        XCTAssertEqual(titleSpan.kind, .text)
        XCTAssertEqual(titleSpan.role, .content)
        XCTAssertEqual(titleSpan.range, titleRange)
        XCTAssertEqual(map.headings.first?.title, "안녕 🦊 e\u{301}")

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let runs = map.runs(in: fullRange)
        XCTAssertEqual(runs.first?.range.location, 0)
        XCTAssertEqual(runs.last.map { NSMaxRange($0.range) }, (text as NSString).length)
        XCTAssertEqual(runs.map(\.range).reduce(0) { $0 + $1.length }, fullRange.length)
    }

    func testRunsClassifyHeadingsAndInlineConstructs() throws {
        let text = "# *em* and **bold**\n\nUse `code`, [link](https://example.test \"title\"), ![alt](image.png).\n"
        let map = MarkdownSourceMap.parse(text)

        XCTAssertEqual(map.headings.first?.title, "em and bold")
        try assertRun("# ", kind: .heading(level: 1), role: .syntax, in: map, text: text)
        try assertRun("*", kind: .emphasis, role: .syntax, in: map, text: text)
        try assertRun("em", kind: .text, role: .content, in: map, text: text)
        try assertRun("**", kind: .strong, role: .syntax, in: map, text: text)
        try assertRun("bold", kind: .text, role: .content, in: map, text: text)
        try assertRun("`", kind: .codeSpan, role: .syntax, in: map, text: text)
        try assertRun("code", kind: .codeSpan, role: .content, in: map, text: text)
        let codeMarkerRange = try XCTUnwrap(range(of: "`", in: text))
        XCTAssertEqual(map.span(at: codeMarkerRange.location)?.kind, .codeSpan)
        XCTAssertEqual(map.span(at: codeMarkerRange.location)?.role, .syntax)
        try assertRun("[", kind: .link, role: .syntax, in: map, text: text)
        try assertRun("](https://example.test \"title\")", kind: .link, role: .syntax, in: map, text: text)
        try assertRun("![", kind: .image, role: .syntax, in: map, text: text)
        try assertRun("](image.png)", kind: .image, role: .syntax, in: map, text: text)
    }

    func testRunsClassifyStrikethroughAutolinkListsQuotesAndFences() throws {
        let text = "- [x] checked\n1. ordered\n> quoted\n\n~~removed~~ https://example.test <https://angle.test>\n```swift info\n# not a heading\n```\n"
        let map = MarkdownSourceMap.parse(text)

        try assertRun("- [x] ", kind: .listItem(ordered: false, taskState: .checked), role: .syntax, in: map, text: text)
        try assertRun("1. ", kind: .listItem(ordered: true, taskState: nil), role: .syntax, in: map, text: text)
        try assertRun("> ", kind: .blockQuote, role: .syntax, in: map, text: text)
        try assertRun("~~", kind: .strikethrough, role: .syntax, in: map, text: text)
        try assertRun("<", kind: .autolink, role: .syntax, in: map, text: text)
        try assertRun("```swift info", kind: .codeBlock(fenced: true), role: .syntax, in: map, text: text)
        try assertRun("# not a heading\n", kind: .codeBlock(fenced: true), role: .content, in: map, text: text)
        try assertRun("```", kind: .codeBlock(fenced: true), role: .syntax, in: map, text: text)

        XCTAssertTrue(map.headings.isEmpty)
    }

    func testLeadingFrontMatterIsOneSyntaxSpanAndBodyPositionsRemainStable() throws {
        let text = "---\ntitle: 🦊\n---\n# Heading\n"
        let map = MarkdownSourceMap.parse(text)
        let frontMatterText = "---\ntitle: 🦊\n---"
        let frontMatterRange = try XCTUnwrap(range(of: frontMatterText, in: text))
        let frontMatterSpan = try XCTUnwrap(map.span(at: 0))

        XCTAssertEqual(frontMatterSpan.kind, .frontMatter)
        XCTAssertEqual(frontMatterSpan.role, .syntax)
        XCTAssertEqual(frontMatterSpan.range, frontMatterRange)
        try assertRun(frontMatterText, kind: .frontMatter, role: .syntax, in: map, text: text)

        let headingRange = try XCTUnwrap(range(of: "# ", in: text))
        XCTAssertEqual(map.span(at: headingRange.location)?.kind, .heading(level: 1))
        XCTAssertEqual(map.headings, [HeadingNode(level: 1, title: "Heading", lineNumber: 3)])
    }

    func testSetextHeadingsUseTheTextLineAndStripInlineMarks() {
        let text = "Title **bold**\n======\n\nSubtitle\n------\n"
        let headings = MarkdownSourceMap.parse(text).headings

        XCTAssertEqual(headings, [
            HeadingNode(level: 1, title: "Title bold", lineNumber: 0),
            HeadingNode(level: 2, title: "Subtitle", lineNumber: 3),
        ])
    }

    func testSetextUnderlinesAreHeadingSyntaxEvenBeforeBlankLines() throws {
        let text = "Title\n=====\n\nSubtitle\n-----\n\nTail\n"
        let map = MarkdownSourceMap.parse(text)

        try assertRun("=====", kind: .heading(level: 1), role: .syntax, in: map, text: text)
        try assertRun("-----", kind: .heading(level: 2), role: .syntax, in: map, text: text)
        try assertRun("Title", kind: .text, role: .content, in: map, text: text)
        let tail = try XCTUnwrap(range(of: "Tail", in: text))
        XCTAssertEqual(map.span(at: tail.location)?.kind, .text)
        let blank = try XCTUnwrap(range(of: "\n\n", in: text))
        XCTAssertEqual(map.span(at: blank.location + 1)?.kind, .text)
    }

    func testBlockSpansEndingBeforeBlankLinesRemainInMap() throws {
        let text = "- item\n\n---\n\nAfter\n"
        let map = MarkdownSourceMap.parse(text)

        try assertRun("- ", kind: .listItem(ordered: false, taskState: nil), role: .syntax, in: map, text: text)
        try assertRun("---", kind: .thematicBreak, role: .syntax, in: map, text: text)
    }

    func testHeadingLikeTextInsideFencedCodeIsNotExtracted() {
        let text = "```markdown\n# not a heading\n```\n# actual heading\n"
        let headings = MarkdownSourceMap.parse(text).headings

        XCTAssertEqual(headings, [HeadingNode(level: 1, title: "actual heading", lineNumber: 3)])
    }

    func testParsePerformanceForRoughly200KBDocument() {
        let prose = String(repeating: "This sentence keeps the sample representative of an editor document with ordinary prose, links, and Unicode notes. ", count: 600)
        let sample = """
        # Heading with **bold** and *emphasis*
        A paragraph with [a link](https://example.com), `inline code`, and ~~strike~~. \(prose)
        - [x] checked task
        > quoted text with https://example.com
        ```swift info
        let value = 42
        ```

        """
        let repetitions = (200_000 / sample.utf8.count) + 1
        let text = String(repeating: sample, count: repetitions)

        let start = CFAbsoluteTimeGetCurrent()
        let map = MarkdownSourceMap.parse(text)
        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1_000

        print("MarkdownSourceMap 200 KB parse: \(elapsedMilliseconds) ms")
        XCTAssertGreaterThanOrEqual(text.utf8.count, 200_000)
        XCTAssertFalse(map.headings.isEmpty)
        XCTAssertLessThan(elapsedMilliseconds, 30)
    }

    func testDocumentTextRevisionAdvancesOnlyWhenContentChanges() {
        let document = Document(rawText: "Initial")

        XCTAssertEqual(document.textRevision, 0)
        document.rawText = "Updated"
        XCTAssertEqual(document.textRevision, 1)
        document.rawText = "Updated"
        XCTAssertEqual(document.textRevision, 1)
        document.rawText = "Updated again"
        XCTAssertEqual(document.textRevision, 2)
    }


    func testFirstH1Title() {
        let text = "# Hello World\n\nSome text\n\n## Section"
        XCTAssertEqual(MarkdownSourceMap.parse(text).firstH1Title, "Hello World")
    }

    func testFirstH1TitleIgnoresH2() {
        let text = "## Not H1\n\n# Actual H1"
        XCTAssertEqual(MarkdownSourceMap.parse(text).firstH1Title, "Actual H1")
    }

    func testFirstH1LetterUppercase() {
        let text = "# my document"
        XCTAssertEqual(MarkdownSourceMap.parse(text).firstH1Letter, "M")
    }

    func testParseHeadings() {
        let text = """
        # Title
        Some text
        ## Section One
        ### Subsection
        ## Section Two
        """
        let headings = MarkdownSourceMap.parse(text).headings
        XCTAssertEqual(headings.count, 4)
        XCTAssertEqual(headings[0].level, 1)
        XCTAssertEqual(headings[0].title, "Title")
        XCTAssertEqual(headings[1].level, 2)
        XCTAssertEqual(headings[1].title, "Section One")
        XCTAssertEqual(headings[2].level, 3)
        XCTAssertEqual(headings[2].title, "Subsection")
    }

    func testEmptyDocument() {
        XCTAssertNil(MarkdownSourceMap.parse("").firstH1Title)
        XCTAssertNil(MarkdownSourceMap.parse("").firstH1Letter)
        XCTAssertTrue(MarkdownSourceMap.parse("").headings.isEmpty)
    }

    func testDocumentTableOfContentsStartsExpanded() {
        XCTAssertTrue(Document().isTOCExpanded)
    }

    func testDocumentCachesSidebarPresentationMetadata() {
        let document = Document(rawText: "# 🦊 Fox Notes\nBody")

        XCTAssertEqual(document.displayTitle, "🦊 Fox Notes")
        XCTAssertEqual(document.sidebarDisplayTitle, "Fox Notes")
        XCTAssertEqual(document.faviconLetter, "🦊")
        XCTAssertTrue(document.hasH1)

        document.rawText = "# Revised Notes\nBody"
        document.headings = MarkdownSourceMap.parse(document.rawText).headings

        XCTAssertEqual(document.displayTitle, "Revised Notes")
        XCTAssertEqual(document.sidebarDisplayTitle, "Revised Notes")
        XCTAssertEqual(document.faviconLetter, "R")
        XCTAssertTrue(document.hasH1)
    }

    func testSidebarMetadataAccessStaysConstantWithLargeDocuments() {
        let body = String(repeating: "body text without headings\n", count: 4_000)
        let documents = (0..<33).map { index in
            Document(
                fileURL: URL(fileURLWithPath: "/tmp/Document-\(index).md"),
                rawText: body
            )
        }
        var sink = 0

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<20 {
            for document in documents {
                sink += document.displayTitle.utf8.count
                sink += document.sidebarDisplayTitle.utf8.count
                sink += document.faviconLetter.utf8.count
                sink += document.hasH1 ? 1 : 0
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertGreaterThan(sink, 0)
        XCTAssertLessThan(elapsed, 0.5)
    }

    func testSidebarTOCRowsComputeVisibilityAndChildrenInOnePass() {
        let headings = MarkdownSourceMap.parse("""
        # Document
        ## First
        ### First child
        ## Second
        ### Second child
        """).headings
        guard let first = headings.first(where: { $0.title == "First" }) else {
            return XCTFail("The first TOC heading was not parsed")
        }

        let expandedRows = SidebarTOCModel.rows(
            headings: headings,
            collapsedHeadingIDs: []
        )
        XCTAssertEqual(expandedRows.map(\.heading.title), [
            "First", "First child", "Second", "Second child",
        ])
        XCTAssertEqual(expandedRows.map(\.hasChildren), [true, false, true, false])

        let collapsedRows = SidebarTOCModel.rows(
            headings: headings,
            collapsedHeadingIDs: [first.id]
        )
        XCTAssertEqual(collapsedRows.map(\.heading.title), [
            "First", "Second", "Second child",
        ])
    }

    func testSidebarKeepsEveryExpandedDocumentAsATOCSection() {
        let expandedStates = [true, false, true, true, false]
        let visibleCount = expandedStates.reduce(into: 0) { count, isExpanded in
            if SidebarDocumentModel.showsTableOfContents(
                isExpanded: isExpanded,
                hasHeadings: true,
                isDragging: false
            ) {
                count += 1
            }
        }

        XCTAssertEqual(visibleCount, 3)
        XCTAssertFalse(SidebarDocumentModel.showsTableOfContents(
            isExpanded: true,
            hasHeadings: true,
            isDragging: true
        ))
    }

    func testSidebarKeepsVisitedDocumentsMountedForTOCAnimation() {
        let activeID = UUID()
        let visitedInactiveID = UUID()
        let unvisitedInactiveID = UUID()
        let mountedIDs: Set<UUID> = [visitedInactiveID]

        XCTAssertTrue(SidebarDocumentModel.mountsTableOfContentsSection(
            documentID: activeID,
            activeDocumentID: activeID,
            mountedDocumentIDs: mountedIDs
        ))
        XCTAssertTrue(SidebarDocumentModel.mountsTableOfContentsSection(
            documentID: visitedInactiveID,
            activeDocumentID: activeID,
            mountedDocumentIDs: mountedIDs
        ))
        XCTAssertFalse(SidebarDocumentModel.mountsTableOfContentsSection(
            documentID: unvisitedInactiveID,
            activeDocumentID: activeID,
            mountedDocumentIDs: mountedIDs
        ))
    }

    @MainActor
    func testMarkdownFileIconsShareOneWorkspaceLookup() {
        let cache = DocumentFileIconCache()
        let icons = (0..<200).map { index in
            cache.icon(for: URL(fileURLWithPath: "/tmp/Document-\(index).md"))
        }

        XCTAssertEqual(cache.workspaceLookupCount, 1)
        XCTAssertTrue(icons.dropFirst().allSatisfy { $0 === icons[0] })
    }

    func testDocumentReloadsOnlyAfterBackingFileChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkfopsFileSignatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Document.md")
        try "# Original\nBody".write(to: url, atomically: true, encoding: .utf8)
        let document = Document(fileURL: url, rawText: "# Original\nBody")
        document.headings = MarkdownSourceMap.parse(document.rawText).headings

        document.reloadFromDiskIfChanged()
        XCTAssertEqual(document.rawText, "# Original\nBody")

        try "# Replacement\nChanged body".write(to: url, atomically: true, encoding: .utf8)
        document.reloadFromDiskIfChanged()

        XCTAssertEqual(document.rawText, "# Replacement\nChanged body")
        XCTAssertEqual(document.displayTitle, "Replacement")
    }

    func testHeadingLineNumbers() {
        let text = "Intro\n# Title\nBody\n## Sub"
        let headings = MarkdownSourceMap.parse(text).headings
        XCTAssertEqual(headings[0].lineNumber, 1)
        XCTAssertEqual(headings[1].lineNumber, 3)
    }

    func testDocumentCoordinatorRoutesExternalOpenToMostRecentWindow() {
        let coordinator = makeTestCoordinator()
        let first = coordinator.session(for: UUID())!
        let second = coordinator.session(for: UUID())!
        coordinator.touch(sessionID: second.id)

        let url = URL(fileURLWithPath: "/tmp/markfops-route-\(UUID().uuidString).md")
        let document = coordinator.open(url: url)

        XCTAssertIdentical(document, second.store.documents.first)
        XCTAssertTrue(first.store.documents.isEmpty)
    }

    func testDocumentCoordinatorFocusesExistingOwner() {
        let coordinator = makeTestCoordinator()
        let first = coordinator.session(for: UUID())!
        let second = coordinator.session(for: UUID())!
        let url = URL(fileURLWithPath: "/tmp/markfops-owner-\(UUID().uuidString).md")
        let document = first.store.openLocally(url: url)
        second.store.newDocument()

        let reopened = coordinator.open(url: url)

        XCTAssertIdentical(reopened, document)
        XCTAssertEqual(first.store.activeID, document.id)
        XCTAssertTrue(second.store.documents.allSatisfy { $0.id != document.id })
    }

    func testMovePreservesIdentityAndDirtyState() {
        let coordinator = makeTestCoordinator()
        let source = coordinator.session(for: UUID())!
        let destination = coordinator.session(for: UUID())!
        let document = source.store.newDocument()
        document.rawText = "# Changed"
        document.isDirty = true

        coordinator.move(documentID: document.id, from: source.id, to: destination.id)

        XCTAssertIdentical(destination.store.documents.first, document)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.rawText, "# Changed")
        XCTAssertNil(coordinator.sessions[source.id])
    }

    func testMovingFinalTabRemovesEmptySourceSession() {
        let coordinator = makeTestCoordinator()
        let source = coordinator.session(for: UUID())!
        let destination = coordinator.session(for: UUID())!
        let document = source.store.newDocument()

        coordinator.move(documentID: document.id, from: source.id, to: destination.id)

        XCTAssertNil(coordinator.sessions[source.id])
        XCTAssertTrue(destination.store.documents.contains(document))
    }

    func testRecoverySnapshotMigratesFlatPayload() throws {
        let document = RecoveryDocumentSnapshot(
            id: UUID(), displayTitle: "Untitled", fileURLString: nil,
            rawText: "draft", savedText: "", isDirty: true
        )
        let flatJSON = """
        {"documents":[{"id":"\(document.id.uuidString)","displayTitle":"Untitled","rawText":"draft","savedText":"","isDirty":true}],"activeID":"\(document.id.uuidString)"}
        """
        let migrated = try JSONDecoder().decode(
            RecoverySnapshot.self,
            from: Data(flatJSON.utf8)
        )

        XCTAssertEqual(migrated.windows.count, 1)
        XCTAssertEqual(migrated.documents.map(\.id), [document.id])
        XCTAssertEqual(migrated.activeID, document.id)
        XCTAssertTrue(migrated.documents[0].isTOCExpanded)
        XCTAssertEqual(migrated.tocExpansionDefaultsVersion, 0)
    }

    func testRecoverySnapshotRoundTripsMultipleWindows() throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstDocument = RecoveryDocumentSnapshot(
            id: UUID(), displayTitle: "First", fileURLString: nil,
            rawText: "one", savedText: "", isDirty: true
        )
        let secondDocument = RecoveryDocumentSnapshot(
            id: UUID(), displayTitle: "Second", fileURLString: nil,
            rawText: "two", savedText: "", isDirty: true
        )
        let snapshot = RecoverySnapshot(windows: [
            RecoveryWindowSnapshot(id: firstID, documents: [firstDocument], activeID: firstDocument.id),
            RecoveryWindowSnapshot(id: secondID, documents: [secondDocument], activeID: secondDocument.id)
        ], activeWindowID: secondID)

        let restored = try JSONDecoder().decode(
            RecoverySnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(restored.windows.map(\.id), [firstID, secondID])
        XCTAssertEqual(restored.activeWindowID, secondID)
        XCTAssertEqual(restored.documents.map(\.id), [firstDocument.id, secondDocument.id])
        XCTAssertEqual(
            restored.tocExpansionDefaultsVersion,
            RecoverySnapshot.currentTOCExpansionDefaultsVersion
        )
    }

    func testDocumentCannotAppearInTwoStoresAfterMove() {
        let coordinator = makeTestCoordinator()
        let source = coordinator.session(for: UUID())!
        let destination = coordinator.session(for: UUID())!
        let document = source.store.newDocument()

        coordinator.move(documentID: document.id, from: source.id, to: destination.id)

        let occurrences = coordinator.sessions.values.reduce(into: 0) { count, session in
            count += session.store.documents.filter { $0.id == document.id }.count
        }
        XCTAssertEqual(occurrences, 1)
    }

    func testWindowRegistrationRefreshDoesNotStealMostRecentWindow() {
        let coordinator = makeTestCoordinator()
        let first = coordinator.session(for: UUID())!
        let second = coordinator.session(for: UUID())!
        let firstWindow = NSWindow(contentRect: .zero, styleMask: .borderless,
                                   backing: .buffered, defer: true)
        let secondWindow = NSWindow(contentRect: .zero, styleMask: .borderless,
                                    backing: .buffered, defer: true)

        coordinator.registerWindow(id: first.id, window: firstWindow)
        coordinator.registerWindow(id: second.id, window: secondWindow)
        coordinator.touch(sessionID: second.id)
        coordinator.registerWindow(id: first.id, window: firstWindow)

        XCTAssertEqual(coordinator.lastActiveWindowID, second.id)
    }

    func testWindowRegistrationReplaysPendingFocusOnce() {
        let coordinator = makeTestCoordinator()
        let session = coordinator.session(for: UUID())!
        let document = session.store.newDocument()
        let targetWindow = CoordinatorFocusTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { targetWindow.orderOut(nil) }

        coordinator.focus(sessionID: session.id, documentID: document.id)
        XCTAssertNil(session.window)
        XCTAssertEqual(coordinator.pendingWindowFocus[session.id]?.documentID, document.id)
        XCTAssertEqual(coordinator.pendingInitialWindowID, session.id)
        XCTAssertTrue(coordinator.needsInitialScenePresentation)

        coordinator.registerWindow(id: session.id, window: targetWindow)
        XCTAssertNil(coordinator.pendingWindowFocus[session.id])
        XCTAssertNil(coordinator.pendingInitialWindowID)
        XCTAssertFalse(coordinator.needsInitialScenePresentation)
        XCTAssertTrue(targetWindow.isVisible)
        XCTAssertEqual(session.store.activeID, document.id)

        coordinator.registerWindow(id: session.id, window: targetWindow)
        XCTAssertNil(coordinator.pendingWindowFocus[session.id])
    }

    func testColdOpenWithoutSessionRequestsEmptyInitialScene() throws {
        let coordinator = makeTestCoordinator()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markfops-cold-open-\(UUID().uuidString).md")
        try "# Cold Open".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        coordinator.open(urls: [fileURL])

        XCTAssertTrue(coordinator.sessions.isEmpty)
        XCTAssertTrue(coordinator.needsInitialScenePresentation)

        var requestedIDs: [UUID] = []
        coordinator.install(openWindow: { requestedIDs.append($0) })
        XCTAssertTrue(coordinator.presentInitialSceneIfNeeded())

        let session = try XCTUnwrap(coordinator.sessions.values.first)
        XCTAssertTrue(session.store.documents.isEmpty)
        XCTAssertFalse(coordinator.needsInitialScenePresentation)
        XCTAssertEqual(requestedIDs, [session.id])

        XCTAssertFalse(coordinator.presentInitialSceneIfNeeded())
        XCTAssertEqual(requestedIDs, [session.id])

        let window = CoordinatorFocusTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        coordinator.registerWindow(id: session.id, window: window)

        XCTAssertEqual(session.store.documents.count, 1)
        XCTAssertEqual(session.store.activeDocument?.displayTitle, "Cold Open")
        XCTAssertTrue(window.isVisible)
    }

    func testPendingPresentationIsNotRequestedTwiceWhenOpenWindowIsInstalled() {
        let coordinator = makeTestCoordinator()
        let session = coordinator.newWindow(withNewDocument: false)
        coordinator.focus(sessionID: session.id)

        var requestedIDs: [UUID] = []
        coordinator.install(openWindow: { requestedIDs.append($0) })
        XCTAssertTrue(coordinator.presentInitialSceneIfNeeded())

        XCTAssertEqual(requestedIDs, [session.id])
    }

    func testTransientLaunchWindowClosePreservesItsSession() {
        let coordinator = makeTestCoordinator()
        let session = coordinator.session(for: UUID())!
        let window = CoordinatorFocusTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        coordinator.registerWindow(id: session.id, window: window)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        XCTAssertNotNil(coordinator.sessions[session.id])
        XCTAssertNil(session.window)

        coordinator.finishLaunching()
        coordinator.registerWindow(id: session.id, window: window)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        XCTAssertNil(coordinator.sessions[session.id])
    }

    func testClosingWindowlessSessionClearsPendingFocus() {
        let coordinator = makeTestCoordinator()
        let session = coordinator.session(for: UUID())!
        let document = session.store.newDocument()

        coordinator.focus(sessionID: session.id, documentID: document.id)
        XCTAssertNotNil(coordinator.pendingWindowFocus[session.id])

        coordinator.closeWindow(id: session.id)

        XCTAssertNil(coordinator.sessions[session.id])
        XCTAssertNil(coordinator.pendingWindowFocus[session.id])
    }

    func testConcurrentSceneBootstrapDoesNotReuseTabCatalog() {
        let coordinator = makeTestCoordinator()

        let firstID = coordinator.bootstrapWindowID()
        let secondID = coordinator.bootstrapWindowID()

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertNotIdentical(coordinator.store(for: firstID), coordinator.store(for: secondID))
    }

    func testActiveDocumentChangesRefreshItsWindowAppearance() {
        let coordinator = makeTestCoordinator()
        let session = coordinator.session(for: UUID())!
        let window = NSWindow(contentRect: .zero, styleMask: .borderless,
                              backing: .buffered, defer: true)
        coordinator.registerWindow(id: session.id, window: window)
        let document = session.store.newDocument()

        document.rawText = "# Updated"
        document.headings = MarkdownSourceMap.parse(document.rawText).headings
        document.isDirty = true

        XCTAssertEqual(window.title, "Updated")
        XCTAssertTrue(window.isDocumentEdited)
    }

    func testTabDragDisplacementUsesGlobalCoordinatesAndThreshold() {
        let translation = TabDragState.displacement(
            from: NSPoint(x: 85, y: 73),
            to: NSPoint(x: 420, y: 210)
        )

        XCTAssertEqual(translation.width, 335)
        XCTAssertEqual(translation.height, -137)
        XCTAssertTrue(TabDragState.shouldDetach(translation: translation))
        XCTAssertFalse(TabDragState.shouldDetach(translation: CGSize(width: 60, height: 0)))
    }

    func testCoordinatorPersistenceUsesInjectedRecoveryDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkfopsTests-\(UUID().uuidString)", isDirectory: true)
        let coordinator = DocumentCoordinator(recoveryDirectoryURL: directory)
        let session = coordinator.session(for: UUID())!
        let document = session.store.newDocument()
        document.rawText = "draft"
        document.isDirty = true

        coordinator.persistSession()

        let snapshotURL = directory.appendingPathComponent("RecoverySession.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertTrue(String(data: try Data(contentsOf: snapshotURL), encoding: .utf8)?.contains(document.id.uuidString) == true)
    }

    private func makeTestCoordinator() -> DocumentCoordinator {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkfopsTests-\(UUID().uuidString)", isDirectory: true)
        return DocumentCoordinator(recoveryDirectoryURL: directory)
    }

    private func range(of needle: String, in text: String) -> NSRange? {
        let range = (text as NSString).range(of: needle)
        return range.location == NSNotFound ? nil : range
    }

    private func assertRun(
        _ needle: String,
        kind: MarkdownSourceMap.Kind,
        role: MarkdownSourceMap.Role,
        in map: MarkdownSourceMap,
        text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let needleRange = try XCTUnwrap(range(of: needle, in: text), file: file, line: line)
        XCTAssertTrue(
            map.runs(in: needleRange).contains {
                $0.range == needleRange && $0.kind == kind && $0.role == role
            },
            "Expected a \(role) \(kind) run for \(needle.debugDescription)",
            file: file,
            line: line
        )
    }
}

private final class CoordinatorFocusTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
