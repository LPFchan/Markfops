import AppKit
import Darwin
import Observation

@Observable
final class DocumentStore {
    @ObservationIgnored private let recoveryStore = RecoveryStore()
    @ObservationIgnored private var pendingRecoverySave: DispatchWorkItem?
    @ObservationIgnored private var isRestoringRecovery = false

    init() {
        updateCrashRecoveryMetadata(using: RecoverySnapshot(documents: [], activeID: nil))
    }

    private(set) var documents: [Document] = []
    var activeID: UUID? {
        didSet {
            guard activeID != oldValue else { return }
            activeDocument?.reloadFromDiskIfClean(restartWatching: true)
            activeDocument?.reconcileActiveHeadingWithCurrentContent()
            scheduleRecoverySave()
        }
    }

    var activeDocument: Document? {
        guard let id = activeID else { return nil }
        return documents.first(where: { $0.id == id })
    }

    // MARK: - Document lifecycle

    @discardableResult
    func newDocument() -> Document {
        let doc = Document()
        observe(doc)
        documents.append(doc)
        activeID = doc.id
        return doc
    }

    @discardableResult
    func open(url: URL) -> Document {
        if let existing = documents.first(where: { $0.fileURL == url }) {
            activeID = existing.id
            return existing
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let doc = Document(fileURL: url, rawText: text)
        observe(doc)
        doc.headings = HeadingParser.parseHeadings(in: text)
        documents.append(doc)
        activeID = doc.id
        doc.startWatching()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        return doc
    }

    func save(_ document: Document) throws {
        guard let url = document.fileURL else {
            try saveAs(document)
            return
        }
        try document.rawText.write(to: url, atomically: true, encoding: .utf8)
        document.savedText = document.rawText
        document.isDirty = false
        updateProxyIcon(for: document)
        document.startWatching()
    }

    func saveAs(_ document: Document) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = document.displayTitle + ".md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try document.rawText.write(to: url, atomically: true, encoding: .utf8)
        document.savedText = document.rawText
        document.fileURL = url
        document.isDirty = false
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        updateProxyIcon(for: document)
        document.startWatching()
    }

    // MARK: - Duplicate

    @discardableResult
    func duplicate(_ document: Document) -> Document {
        let copy = Document(rawText: document.rawText)
        observe(copy)
        copy.isDirty = true
        documents.insert(copy, at: (documents.firstIndex(of: document) ?? documents.count - 1) + 1)
        activeID = copy.id
        return copy
    }

    // MARK: - Rename

    /// Inline rename: renames the file on disk using `newBaseName` (no extension).
    /// Called from the tab-pill text field; context-menu "Rename…" still uses `rename(_:)`.
    func renameInline(document: Document, newBaseName: String) {
        guard let currentURL = document.fileURL else { return }
        let newURL = currentURL.deletingLastPathComponent()
            .appendingPathComponent(newBaseName)
            .appendingPathExtension("md")
        guard newURL != currentURL else { return }
        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            document.fileURL = newURL
            document.isDirty = false
            NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
            updateProxyIcon(for: document)
            document.startWatching()
        } catch {
            presentError(error)
        }
    }

    func rename(_ document: Document) {
        guard let currentURL = document.fileURL else {
            try? saveAs(document)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = currentURL.lastPathComponent
        panel.directoryURL = currentURL.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.prompt = NSLocalizedString("Rename", comment: "Rename panel button")
        panel.message = NSLocalizedString("Rename document", comment: "Rename panel message")
        guard panel.runModal() == .OK, let newURL = panel.url else { return }
        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            document.fileURL = newURL
            document.isDirty = false
            NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
            updateProxyIcon(for: document)
            document.startWatching()
        } catch {
            presentError(error)
        }
    }

    // MARK: - Move To

    func moveTo(_ document: Document) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = document.fileURL?.lastPathComponent ?? (document.displayTitle + ".md")
        if let dir = document.fileURL?.deletingLastPathComponent() {
            panel.directoryURL = dir
        }
        panel.canCreateDirectories = true
        panel.prompt = NSLocalizedString("Move", comment: "Move panel button")
        panel.message = NSLocalizedString("Move document to a new location", comment: "Move panel message")
        guard panel.runModal() == .OK, let newURL = panel.url else { return }
        if let oldURL = document.fileURL {
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } catch {
                presentError(error)
                return
            }
        }
        document.fileURL = newURL
        document.isDirty = false
        NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
        updateProxyIcon(for: document)
        document.startWatching()
    }

    // MARK: - Revert to Saved

    func revertToSaved(_ document: Document) {
        guard let url = document.fileURL else { return }
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Revert \"%@\" to saved version?", comment: "Revert alert title"), document.displayTitle)
        alert.informativeText = NSLocalizedString("Your unsaved changes will be lost.", comment: "Revert alert body")
        alert.addButton(withTitle: NSLocalizedString("Revert", comment: "Revert confirm button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        showAlert(alert) { response in
            guard response == .alertFirstButtonReturn else { return }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            document.rawText = text
            document.updateTextMetrics()
            document.isDirty = false
            document.headings = HeadingParser.parseHeadings(in: text)
            document.reconcileActiveHeadingWithCurrentContent()
        }
    }

    // MARK: - Export as PDF

    func exportAsPDF(_ document: Document) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = document.displayTitle + ".pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = HTMLTemplate.currentPage(body: MarkdownRenderer.renderHTML(from: document.rawText))
        PDFExporter.export(html: html, to: url)
    }

    // MARK: - Close

    func close(id: UUID) {
        guard let doc = documents.first(where: { $0.id == id }) else { return }
        guard doc.isDirty else { removeDocument(id: id); return }

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Save changes to \"%@\"?", comment: "Alert title when closing a tab with unsaved changes"), doc.displayTitle)
        alert.informativeText = NSLocalizedString("Your changes will be lost if you don't save them.", comment: "Alert body for unsaved changes")
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Save button"))
        alert.addButton(withTitle: NSLocalizedString("Don't Save", comment: "Discard button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        showAlert(alert) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn: try? self.save(doc)
            case .alertSecondButtonReturn: break
            default: return  // Cancel — don't close
            }
            self.removeDocument(id: id)
        }
    }

    // internal (not private) so cross-window drop delegate and file-watch teardown can call it
    func removeDocument(id: UUID) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[idx].onStateChange = nil
        documents[idx].stopWatching()
        documents.remove(at: idx)
        if activeID == id {
            activeID = documents.isEmpty ? nil : documents[min(idx, documents.count - 1)].id
        }
        scheduleRecoverySave()
        // Close this window if it was a single-tab detached window and is now empty.
        if documents.isEmpty, let win = managedWindow {
            DispatchQueue.main.async { win.performClose(nil) }
        }
    }

    /// Set by `detachToNewWindow` so a window that loses its last tab auto-closes.
    @ObservationIgnored weak var managedWindow: NSWindow?

    // MARK: - Detach to new window

    /// Removes `document` from this store and opens it in a brand-new, independent window.
    func detachToNewWindow(_ document: Document) {
        guard let idx = documents.firstIndex(where: { $0.id == document.id }) else { return }
        document.onStateChange = nil
        documents.remove(at: idx)
        if activeID == document.id {
            activeID = documents.isEmpty ? nil : documents[min(idx, documents.count - 1)].id
        }
        scheduleRecoverySave()

        let newStore = DocumentStore()
        newStore.documents = [document]
        newStore.observe(document)
        newStore.activeID  = document.id
        newStore.scheduleRecoverySave()

        let rootView = ContentView()
            .environment(newStore)
            .focusedSceneValue(\.documentStore, newStore)
            .frame(minHeight: 500)

        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = document.displayTitle
        window.setContentSize(NSSize(width: 900, height: 650))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // Track this window so the store can close it when its last tab is removed.
        newStore.managedWindow = window

        // Cascade 20 pt below/right of the key window
        if let src = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isMainWindow }) {
            window.setFrameOrigin(NSPoint(x: src.frame.minX + 20,
                                          y: src.frame.maxY - window.frame.height - 20))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        TabDragState.shared.reset()
    }

    // MARK: - Tab order

    func insertDocument(_ document: Document, at index: Int) {
        let clamped = max(0, min(index, documents.count))
        observe(document)
        documents.insert(document, at: clamped)
        activeID = document.id
    }

    func moveTab(fromOffsets: IndexSet, toOffset: Int) {
        documents.move(fromOffsets: fromOffsets, toOffset: toOffset)
        scheduleRecoverySave()
    }

    func selectNext() {
        guard !documents.isEmpty else { return }
        let idx = documents.firstIndex(where: { $0.id == activeID }) ?? 0
        activeID = documents[(idx + 1) % documents.count].id
    }

    func selectPrevious() {
        guard !documents.isEmpty else { return }
        let idx = documents.firstIndex(where: { $0.id == activeID }) ?? 0
        activeID = documents[(idx - 1 + documents.count) % documents.count].id
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < documents.count else { return }
        activeID = documents[index].id
    }

    // MARK: - Recovery persistence

    func restorePersistedSession() {
        guard documents.isEmpty else { return }
        guard let snapshot = recoveryStore.load() else { return }

        isRestoringRecovery = true
        defer {
            isRestoringRecovery = false
            scheduleRecoverySave()
        }

        var restoredDocuments: [Document] = []

        for documentSnapshot in snapshot.documents {
            let restored = restoreDocument(from: documentSnapshot)
            guard let restored else { continue }
            observe(restored)
            restoredDocuments.append(restored)
        }

        documents = restoredDocuments
        if let activeID = snapshot.activeID,
           restoredDocuments.contains(where: { $0.id == activeID }) {
            self.activeID = activeID
        } else {
            self.activeID = restoredDocuments.first?.id
        }
    }

    func persistSession() {
        saveRecoverySnapshotNow()
    }

    // MARK: - Proxy icon + dirty close button

    private func updateProxyIcon(for document: Document) {
        NSApp.mainWindow?.representedURL = document.fileURL
        NSApp.mainWindow?.title = document.displayTitle
        NSApp.mainWindow?.isDocumentEdited = document.isDirty
    }

    // MARK: - Quit handling (called by AppDelegate, async sheet)

    func reviewUnsavedForQuit(completion: @escaping (Bool) -> Void) {
        let dirty = documents.filter(\.isDirty)
        guard !dirty.isEmpty else { completion(true); return }
        let names = dirty.map(\.displayTitle).joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("You have unsaved changes", comment: "Quit alert title")
        alert.informativeText = String(format: NSLocalizedString("Unsaved documents: %@", comment: "Quit alert body listing document names"), names)
        alert.addButton(withTitle: NSLocalizedString("Review Unsaved\u{2026}", comment: "Save before quitting"))
        alert.addButton(withTitle: NSLocalizedString("Quit Anyway", comment: "Quit without saving"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel quit"))
        showAlert(alert) { [weak self] response in
            guard let self else { completion(false); return }
            switch response {
            case .alertFirstButtonReturn:
                for doc in dirty { try? self.save(doc) }
                completion(true)
            case .alertSecondButtonReturn:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    // MARK: - Helpers

    /// Shows an NSAlert as a sheet when a main window is available, falls back to modal.
    private func showAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func presentError(_ error: Error) {
        if let window = NSApp.mainWindow {
            NSAlert(error: error).beginSheetModal(for: window)
        } else {
            NSAlert(error: error).runModal()
        }
    }

    private func observe(_ document: Document) {
        document.onStateChange = { [weak self] _ in
            self?.scheduleRecoverySave()
        }
    }

    private func scheduleRecoverySave() {
        guard !isRestoringRecovery else { return }
        pendingRecoverySave?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.saveRecoverySnapshotNow()
        }
        pendingRecoverySave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func saveRecoverySnapshotNow() {
        guard !isRestoringRecovery else { return }
        pendingRecoverySave?.cancel()
        pendingRecoverySave = nil
        let snapshot = makeRecoverySnapshot()
        recoveryStore.save(snapshot)
        updateCrashRecoveryMetadata(using: snapshot)
    }

    private func makeRecoverySnapshot() -> RecoverySnapshot {
        let documentSnapshots = documents.compactMap { document -> RecoveryDocumentSnapshot? in
            let fileURLString = document.fileURL?.absoluteString
            let shouldEmbedDraft = document.isDirty || document.fileURL == nil
            let rawText = shouldEmbedDraft ? document.rawText : nil
            let savedText = shouldEmbedDraft ? document.savedText : nil

            guard fileURLString != nil || !(rawText ?? "").isEmpty || document.isDirty else {
                return nil
            }

            return RecoveryDocumentSnapshot(
                id: document.id,
                displayTitle: document.displayTitle,
                fileURLString: fileURLString,
                rawText: rawText,
                savedText: savedText,
                isDirty: document.isDirty
            )
        }

        return RecoverySnapshot(documents: documentSnapshots, activeID: activeID)
    }

    private func restoreDocument(from snapshot: RecoveryDocumentSnapshot) -> Document? {
        let fileURL = snapshot.fileURLString.flatMap(URL.init(string:))

        if let fileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            let diskText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let rawText = snapshot.isDirty ? (snapshot.rawText ?? diskText) : diskText
            let document = Document(id: snapshot.id, fileURL: fileURL, rawText: rawText)
            document.savedText = snapshot.savedText ?? diskText
            document.isDirty = snapshot.isDirty && rawText != document.savedText
            document.headings = HeadingParser.parseHeadings(in: rawText)
            document.startWatching()
            return document
        }

        guard let rawText = snapshot.rawText,
              !rawText.isEmpty || snapshot.isDirty else { return nil }

        let document = Document(id: snapshot.id, rawText: rawText)
        document.savedText = snapshot.savedText ?? ""
        document.isDirty = true
        document.headings = HeadingParser.parseHeadings(in: rawText)
        return document
    }

    private func updateCrashRecoveryMetadata(using snapshot: RecoverySnapshot) {
        let status = recoveryStore.status(for: snapshot, activeDocumentTitle: activeDocument?.displayTitle)
        CrashRecoveryInfoReporter.shared.update(status.crashLogMessage)
    }
}

private struct RecoverySnapshot: Codable {
    var documents: [RecoveryDocumentSnapshot]
    var activeID: UUID?
}

private struct RecoveryDocumentSnapshot: Codable {
    var id: UUID
    var displayTitle: String
    var fileURLString: String?
    var rawText: String?
    var savedText: String?
    var isDirty: Bool
}

private struct RecoveryStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> RecoverySnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? decoder.decode(RecoverySnapshot.self, from: data)
    }

    func save(_ snapshot: RecoverySnapshot) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: draftsDirectoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
            try syncDraftFiles(for: snapshot)
            try writeRecoveryInstructions(for: snapshot)
        } catch {
            NSSound.beep()
        }
    }

    func status(for snapshot: RecoverySnapshot, activeDocumentTitle: String?) -> RecoveryStatus {
        let draftCount = snapshot.documents.filter { $0.rawText != nil }.count
        let activeTitle = activeDocumentTitle ?? snapshot.documents.first(where: { $0.id == snapshot.activeID })?.displayTitle
        let instructionsPath = displayPath(for: instructionsURL)
        let snapshotPath = displayPath(for: snapshotURL)

        var lines = [
            "Markfops crash recovery",
            "Recovery instructions: \(instructionsPath)",
            "Recovery snapshot: \(snapshotPath)",
            "Cached draft files: \(draftCount)"
        ]

        if let activeTitle, !activeTitle.isEmpty {
            lines.append("Active document: \(activeTitle)")
        }

        if draftCount > 0 {
            lines.append("Open RecoveryInstructions.txt to restore unsaved content after a crash.")
        } else {
            lines.append("No unsaved draft content is currently cached.")
        }

        return RecoveryStatus(
            crashLogMessage: lines.joined(separator: "\n"),
            instructionsDisplayPath: instructionsPath,
            snapshotDisplayPath: snapshotPath,
            draftCount: draftCount
        )
    }

    private var directoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("Markfops", isDirectory: true)
    }

    private var snapshotURL: URL {
        directoryURL.appendingPathComponent("RecoverySession.json", isDirectory: false)
    }

    private var instructionsURL: URL {
        directoryURL.appendingPathComponent("RecoveryInstructions.txt", isDirectory: false)
    }

    private var draftsDirectoryURL: URL {
        directoryURL.appendingPathComponent("Drafts", isDirectory: true)
    }

    private func syncDraftFiles(for snapshot: RecoverySnapshot) throws {
        let fileManager = FileManager.default
        let existingDrafts = (try? fileManager.contentsOfDirectory(at: draftsDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for url in existingDrafts {
            try? fileManager.removeItem(at: url)
        }

        for document in snapshot.documents {
            guard let rawText = document.rawText else { continue }
            try rawText.write(to: draftURL(for: document), atomically: true, encoding: .utf8)
        }
    }

    private func writeRecoveryInstructions(for snapshot: RecoverySnapshot) throws {
        let status = status(for: snapshot, activeDocumentTitle: snapshot.documents.first(where: { $0.id == snapshot.activeID })?.displayTitle)
        var lines = [
            "Markfops Crash Recovery",
            "",
            "If the app crashes, the macOS crash report should include the same instructions path shown below under Application Specific Information.",
            "",
            "Recovery instructions: \(status.instructionsDisplayPath)",
            "Recovery snapshot: \(status.snapshotDisplayPath)",
            "Cached draft files: \(status.draftCount)",
            ""
        ]

        if snapshot.documents.isEmpty {
            lines.append("There are currently no recoverable documents cached.")
        } else {
            lines.append("Documents:")
            for document in snapshot.documents {
                let draftPath = document.rawText.map { _ in displayPath(for: draftURL(for: document)) } ?? "none"
                let source = document.fileURLString ?? "unsaved document"
                let state = document.isDirty ? "unsaved changes" : "saved state"
                lines.append("- \(document.displayTitle) [\(state)]")
                lines.append("  Source: \(source)")
                lines.append("  Draft file: \(draftPath)")
            }
        }

        try lines.joined(separator: "\n").write(to: instructionsURL, atomically: true, encoding: .utf8)
    }

    private func draftURL(for document: RecoveryDocumentSnapshot) -> URL {
        let title = sanitizeFileName(document.displayTitle)
        let prefix = document.id.uuidString.prefix(8)
        return draftsDirectoryURL.appendingPathComponent("\(title)-\(prefix).md", isDirectory: false)
    }

    private func sanitizeFileName(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        let cleaned = base.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "-", options: .regularExpression)
        let squashed = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return squashed.isEmpty ? "Untitled" : squashed
    }

    private func displayPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

private struct RecoveryStatus {
    var crashLogMessage: String
    var instructionsDisplayPath: String
    var snapshotDisplayPath: String
    var draftCount: Int
}

@_silgen_name("__crashreporter_info__")
private var crashReporterInfo: UnsafeMutablePointer<CChar>?

private final class CrashRecoveryInfoReporter {
    static let shared = CrashRecoveryInfoReporter()

    private var retainedCString: UnsafeMutablePointer<CChar>?

    func update(_ message: String) {
        let truncated = String(message.prefix(1024))
        let newPointer = strdup(truncated)
        crashReporterInfo = newPointer
        if let oldPointer = retainedCString, oldPointer != newPointer {
            free(oldPointer)
        }
        retainedCString = newPointer
    }

    deinit {
        if let retainedCString {
            free(retainedCString)
        }
    }
}

// MARK: - FocusedValues

import SwiftUI

struct DocumentStoreFocusKey: FocusedValueKey {
    typealias Value = DocumentStore
}

struct SidebarVisibilityKey: FocusedValueKey {
    typealias Value = Binding<NavigationSplitViewVisibility>
}

struct EditorBridgeFocusKey: FocusedValueKey {
    typealias Value = EditorBridge
}

struct PreviewBridgeFocusKey: FocusedValueKey {
    typealias Value = PreviewBridge
}

struct FindControllerFocusKey: FocusedValueKey {
    typealias Value = FindController
}

extension FocusedValues {
    var documentStore: DocumentStore? {
        get { self[DocumentStoreFocusKey.self] }
        set { self[DocumentStoreFocusKey.self] = newValue }
    }

    var sidebarVisibility: Binding<NavigationSplitViewVisibility>? {
        get { self[SidebarVisibilityKey.self] }
        set { self[SidebarVisibilityKey.self] = newValue }
    }

    var editorBridge: EditorBridge? {
        get { self[EditorBridgeFocusKey.self] }
        set { self[EditorBridgeFocusKey.self] = newValue }
    }

    var previewBridge: PreviewBridge? {
        get { self[PreviewBridgeFocusKey.self] }
        set { self[PreviewBridgeFocusKey.self] = newValue }
    }

    var findController: FindController? {
        get { self[FindControllerFocusKey.self] }
        set { self[FindControllerFocusKey.self] = newValue }
    }
}
