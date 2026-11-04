import AppKit
import XCTest
@testable import Markfops

final class DocumentSaveTests: XCTestCase {
    private var directory: URL!
    private var coordinator: DocumentCoordinator!
    private var store: DocumentStore!
    private var saveRequests = 0
    private var errors: [Error] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkfopsDocumentSaveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        coordinator = DocumentCoordinator(recoveryDirectoryURL: directory.appendingPathComponent("Recovery"))
        store = coordinator.store(for: UUID())
        coordinator.touch(sessionID: store.windowID)
        saveRequests = 0
        errors = []
        configure(store)
    }

    override func tearDownWithError() throws {
        coordinator.sessions.values.forEach { session in
            session.store.documents.forEach { $0.stopWatching() }
        }
        store = nil
        coordinator = nil
        try FileManager.default.removeItem(at: directory)
    }

    private func configure(_ store: DocumentStore, response: NSApplication.ModalResponse = .alertFirstButtonReturn) {
        store.alertPresenter = { _, completion in completion(response) }
        store.errorPresenter = { [unowned self] in self.errors.append($0) }
        store.saveDestinationProvider = { [unowned self] _ in
            self.saveRequests += 1
            return nil
        }
    }

    @discardableResult
    private func draft(in target: DocumentStore? = nil) -> Markfops.Document {
        let document = (target ?? store!).newDocument()
        document.rawText = "Unsaved text 🦊"
        document.isDirty = true
        return document
    }

    private var missingDestination: URL {
        directory.appendingPathComponent("Missing/Document.md")
    }

    private func assertRecoverable(_ document: Markfops.Document, file: StaticString = #filePath, line: UInt = #line) throws {
        coordinator.persistSession()
        let restored = DocumentCoordinator(recoveryDirectoryURL: directory.appendingPathComponent("Recovery"))
        restored.restorePersistedSession()
        let recovered = try XCTUnwrap(restored.sessions.values.flatMap { $0.store.documents }
            .first(where: { $0.id == document.id }), file: file, line: line)
        defer { restored.sessions.values.forEach { $0.store.documents.forEach { $0.stopWatching() } } }
        XCTAssertEqual(recovered.rawText, document.rawText, file: file, line: line)
        XCTAssertTrue(recovered.isDirty, file: file, line: line)
    }

    func testSaveAndSaveAsReportCancellationWithoutChangingDraft() throws {
        let document = draft()
        XCTAssertEqual(try store.saveAs(document), .cancelled)
        XCTAssertEqual(try store.save(document), .cancelled)
        XCTAssertNil(document.fileURL)
        XCTAssertEqual(document.savedText, "")
        XCTAssertTrue(document.isDirty)
        try assertRecoverable(document)
    }

    func testSaveAndSaveAsPropagateWriteFailureWithoutChangingSavedState() throws {
        let document = draft()
        document.fileURL = missingDestination
        XCTAssertThrowsError(try store.save(document))
        XCTAssertEqual(document.fileURL, missingDestination)
        document.fileURL = nil
        store.saveDestinationProvider = { [unowned self] _ in self.missingDestination }
        XCTAssertThrowsError(try store.saveAs(document))
        XCTAssertNil(document.fileURL)
        XCTAssertEqual(document.savedText, "")
        XCTAssertTrue(document.isDirty)
        try assertRecoverable(document)
    }

    func testCancelledSaveDuringTabCloseKeepsDirtyWindowAndRecovery() throws {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        store.managedWindow = window
        defer { store.managedWindow = nil }
        let document = draft()
        store.surfaceRegistry.markMounted(document.id)
        store.close(id: document.id)
        XCTAssertEqual(store.documents.map(\.id), [document.id])
        XCTAssertEqual(store.activeID, document.id)
        XCTAssertTrue(store.surfaceRegistry.contains(document.id))
        XCTAssertTrue(window.isDocumentEdited)
        XCTAssertEqual(saveRequests, 1)
        XCTAssertTrue(errors.isEmpty)
        try assertRecoverable(document)
    }

    func testFailedSaveDuringTabClosePresentsErrorAndKeepsRecovery() throws {
        let document = draft()
        document.fileURL = missingDestination
        store.close(id: document.id)
        XCTAssertEqual(store.documents.map(\.id), [document.id])
        XCTAssertEqual(document.savedText, "")
        XCTAssertEqual(errors.count, 1)
        try assertRecoverable(document)
    }

    func testSuccessfulSaveAllowsTabCloseAndWritesText() throws {
        let document = draft()
        let url = directory.appendingPathComponent("Saved.md")
        store.saveDestinationProvider = { _ in url }
        store.close(id: document.id)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(document.savedText, document.rawText)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), document.rawText)

        // A later save to an existing file bypasses the panel and confirms success too.
        document.rawText += " edited"
        document.isDirty = true
        store.saveDestinationProvider = { _ in XCTFail("Existing file must not prompt"); return nil }
        XCTAssertEqual(try store.save(document), .saved)
        document.stopWatching()
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), document.rawText)
    }

    func testDontSaveClosesTabAndPrunesItsRecovery() throws {
        let document = draft()
        coordinator.persistSession()
        configure(store, response: .alertSecondButtonReturn)
        store.close(id: document.id)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertEqual(saveRequests, 0)
        coordinator.persistSession()
        let snapshot = try JSONDecoder().decode(RecoverySnapshot.self, from: Data(contentsOf:
            directory.appendingPathComponent("Recovery/RecoverySession.json")))
        XCTAssertFalse(snapshot.documents.contains(where: { $0.id == document.id }))
    }

    func testRelativeTabCloseStopsAtCancelledSave() {
        let anchor = store.newDocument()
        let first = draft()
        let cancelled = draft()
        let untouched = draft()
        var requests: [UUID] = []
        store.saveDestinationProvider = { [unowned self] document in
            requests.append(document.id)
            return document.id == first.id ? self.directory.appendingPathComponent("First.md") : nil
        }
        store.closeTabs(relativeTo: anchor.id, scope: .others)
        XCTAssertEqual(requests, [first.id, cancelled.id])
        XCTAssertEqual(store.documents.map(\.id), [anchor.id, cancelled.id, untouched.id])
        XCTAssertTrue(cancelled.isDirty)
        XCTAssertTrue(untouched.isDirty)
    }

    func testWindowCloseStopsAfterCancelledSaveAndRetainsAllTabs() throws {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        store.managedWindow = window
        defer { store.managedWindow = nil }
        let first = draft()
        let cancelled = draft()
        let untouched = draft()
        var requests: [UUID] = []
        store.saveDestinationProvider = { [unowned self] document in
            requests.append(document.id)
            return document.id == first.id ? self.directory.appendingPathComponent("First.md") : nil
        }
        coordinator.closeWindow(id: store.windowID)
        XCTAssertNotNil(coordinator.session(for: store.windowID, create: false))
        XCTAssertEqual(requests, [first.id, cancelled.id])
        XCTAssertEqual(store.documents.count, 3)
        XCTAssertFalse(first.isDirty)
        XCTAssertTrue(untouched.isDirty)
        XCTAssertTrue(window.isDocumentEdited)
        try assertRecoverable(cancelled)
        try assertRecoverable(untouched)
    }

    func testWindowCloseStopsAfterWriteFailure() throws {
        let document = draft()
        let untouched = draft()
        store.saveDestinationProvider = { [unowned self] _ in
            self.saveRequests += 1
            return self.missingDestination
        }
        coordinator.closeWindow(id: store.windowID)
        XCTAssertNotNil(coordinator.session(for: store.windowID, create: false))
        XCTAssertEqual(store.documents.count, 2)
        XCTAssertEqual(saveRequests, 1)
        XCTAssertEqual(errors.count, 1)
        XCTAssertNil(document.fileURL)
        try assertRecoverable(document)
        try assertRecoverable(untouched)
    }

    func testWindowCloseAllowsSuccessfulSaveOrExplicitDiscard() throws {
        let responses: [NSApplication.ModalResponse] = [.alertFirstButtonReturn, .alertSecondButtonReturn]
        for response in responses {
            let session = coordinator.newWindow(withNewDocument: false)
            configure(session.store, response: response)
            let document = draft(in: session.store)
            let url = directory.appendingPathComponent("\(session.id).md")
            session.store.saveDestinationProvider = { _ in url }
            coordinator.closeWindow(id: session.id)
            XCTAssertNil(coordinator.session(for: session.id, create: false))
            XCTAssertEqual(FileManager.default.fileExists(atPath: url.path), response == .alertFirstButtonReturn)
            XCTAssertEqual(document.isDirty, response != .alertFirstButtonReturn)
        }
    }

    func testStoreQuitReviewStopsAtCancelledOrFailedSave() {
        let first = draft()
        let untouched = draft()
        for fails in [false, true] {
            var requests: [UUID] = []
            store.saveDestinationProvider = { [unowned self] document in
                requests.append(document.id)
                return fails ? self.missingDestination : nil
            }
            var decisions: [Bool] = []
            store.reviewUnsavedForQuit { decisions.append($0) }
            XCTAssertEqual(decisions, [false])
            XCTAssertEqual(requests, [first.id])
            XCTAssertTrue(first.isDirty)
            XCTAssertTrue(untouched.isDirty)
        }
        XCTAssertEqual(errors.count, 1)
    }

    func testQuitAcrossWindowsStopsAtCancelledOrFailedSave() throws {
        let first = draft()
        let otherStore = coordinator.newWindow(withNewDocument: false).store
        let second = draft(in: otherStore)
        for fails in [false, true] {
            saveRequests = 0
            for target in [store!, otherStore] {
                configure(target)
                target.saveDestinationProvider = { [unowned self] _ in
                    self.saveRequests += 1
                    return fails ? self.missingDestination : nil
                }
            }
            var decisions: [Bool] = []
            coordinator.reviewUnsavedForQuit { decisions.append($0) }
            XCTAssertEqual(decisions, [false])
            XCTAssertEqual(saveRequests, 1)
            XCTAssertEqual(coordinator.sessions.count, 2)
            try assertRecoverable(first)
            try assertRecoverable(second)
        }
        XCTAssertEqual(errors.count, 1)
    }

    func testSuccessfulQuitSavesAllWindows() throws {
        let first = draft()
        let otherStore = coordinator.newWindow(withNewDocument: false).store
        let second = draft(in: otherStore)
        for target in [store!, otherStore] {
            configure(target)
            target.saveDestinationProvider = { [unowned self] document in
                self.directory.appendingPathComponent("\(document.id).md")
            }
        }
        var decisions: [Bool] = []
        coordinator.reviewUnsavedForQuit { decisions.append($0) }
        XCTAssertEqual(decisions, [true])
        for document in [first, second] {
            XCTAssertFalse(document.isDirty)
            XCTAssertEqual(try String(contentsOf: XCTUnwrap(document.fileURL), encoding: .utf8), document.rawText)
        }
    }

    func testQuitAnywayPreservesDirtyDraftsForRecovery() throws {
        let document = draft()
        configure(store, response: .alertSecondButtonReturn)
        var decisions: [Bool] = []
        coordinator.reviewUnsavedForQuit { decisions.append($0) }
        XCTAssertEqual(decisions, [true])
        XCTAssertEqual(saveRequests, 0)
        coordinator.prepareForTermination()
        try assertRecoverable(document)
    }

    func testCancelAtCloseOrQuitAlertKeepsDraftWithoutAttemptingSave() throws {
        let document = draft()
        configure(store, response: .alertThirdButtonReturn)
        store.close(id: document.id)
        coordinator.closeWindow(id: store.windowID)
        var decisions: [Bool] = []
        store.reviewUnsavedForQuit { decisions.append($0) }
        coordinator.reviewUnsavedForQuit { decisions.append($0) }
        XCTAssertEqual(decisions, [false, false])
        XCTAssertEqual(saveRequests, 0)
        XCTAssertEqual(store.documents.map(\.id), [document.id])
        XCTAssertNotNil(coordinator.session(for: store.windowID, create: false))
        try assertRecoverable(document)
    }
}
