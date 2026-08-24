import XCTest
@testable import Markfops

final class DocumentWatcherTests: XCTestCase {
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
