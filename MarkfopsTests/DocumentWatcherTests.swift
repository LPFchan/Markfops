import XCTest
@testable import Markfops

final class DocumentWatcherTests: XCTestCase {
    func testCollapsedTabSizingKeepsOnlyTheActiveTabModeratelyWide() {
        let collapsedWidth: CGFloat = 32

        XCTAssertEqual(
            TabPillSizing.resolvedWidth(baseWidth: collapsedWidth, isActive: false),
            collapsedWidth
        )
        XCTAssertEqual(
            TabPillSizing.resolvedWidth(baseWidth: collapsedWidth, isActive: true),
            TabPillSizing.collapsedActiveWidth
        )

        let roomyWidth: CGFloat = 90
        XCTAssertEqual(
            TabPillSizing.resolvedWidth(baseWidth: roomyWidth, isActive: true),
            roomyWidth
        )
    }

    func testShortTabRowsCenterWithinTheToolbarViewport() {
        XCTAssertEqual(
            TabPillSizing.minimumCenteredContentWidth(toolbarWidth: 900),
            848
        )
        XCTAssertEqual(
            TabPillSizing.minimumCenteredContentWidth(toolbarWidth: 40),
            0
        )
    }

    func testRelativeTabCloseScopesKeepTheExpectedDocuments() {
        let leftStore = DocumentStore()
        let leftDocuments = (0..<5).map { _ in leftStore.newDocument() }
        leftStore.closeTabs(relativeTo: leftDocuments[2].id, scope: .left)
        XCTAssertEqual(leftStore.documents.map(\.id), Array(leftDocuments[2...]).map(\.id))

        let rightStore = DocumentStore()
        let rightDocuments = (0..<5).map { _ in rightStore.newDocument() }
        rightStore.closeTabs(relativeTo: rightDocuments[2].id, scope: .right)
        XCTAssertEqual(rightStore.documents.map(\.id), Array(rightDocuments[...2]).map(\.id))

        let othersStore = DocumentStore()
        let otherDocuments = (0..<5).map { _ in othersStore.newDocument() }
        othersStore.closeTabs(relativeTo: otherDocuments[2].id, scope: .others)
        XCTAssertEqual(othersStore.documents.map(\.id), [otherDocuments[2].id])
    }

    func testOnlyActiveDocumentWatchesAndInactiveChangesReloadOnSelection() throws {
        let directory = try makeTemporaryDirectory()
        let firstURL = directory.appendingPathComponent("First.md")
        let secondURL = directory.appendingPathComponent("Second.md")
        try "# First\nOriginal".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# Second\nOriginal".write(to: secondURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        defer {
            store.documents.forEach { $0.stopWatching() }
            try? FileManager.default.removeItem(at: directory)
        }

        let first = store.open(url: firstURL)
        XCTAssertTrue(first.isWatchingFile)

        let second = store.open(url: secondURL)
        XCTAssertFalse(first.isWatchingFile)
        XCTAssertTrue(second.isWatchingFile)

        try "# First\nChanged while inactive".write(
            to: firstURL,
            atomically: true,
            encoding: .utf8
        )
        store.activeID = first.id

        XCTAssertTrue(first.isWatchingFile)
        XCTAssertFalse(second.isWatchingFile)
        XCTAssertEqual(first.rawText, "# First\nChanged while inactive")
    }

    func testBulkOpenCreatesOnlyFinalDocumentWatcher() throws {
        let directory = try makeTemporaryDirectory()
        let recoveryDirectory = directory.appendingPathComponent("Recovery", isDirectory: true)
        let urls = try (0..<64).map { index -> URL in
            let url = directory.appendingPathComponent("Document-\(index).md")
            try "# Document \(index)\nBody".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        let coordinator = DocumentCoordinator(recoveryDirectoryURL: recoveryDirectory)
        let session = coordinator.session(for: UUID())!
        defer {
            session.store.documents.forEach { $0.stopWatching() }
            try? FileManager.default.removeItem(at: directory)
        }

        coordinator.open(urls: urls, preferredWindowID: session.id)

        XCTAssertEqual(session.store.documents.count, urls.count)
        XCTAssertEqual(session.store.documents.filter(\.isWatchingFile).count, 1)
        XCTAssertEqual(session.store.activeDocument?.fileURL, urls.last)
        XCTAssertTrue(session.store.activeDocument?.isWatchingFile == true)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkfopsDocumentWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
