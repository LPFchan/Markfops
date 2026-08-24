import AppKit
import Darwin
import Observation

@Observable
final class DocumentStore {
    let windowID: UUID
    @ObservationIgnored weak var coordinator: DocumentCoordinator?
    @ObservationIgnored weak var managedWindow: NSWindow?
    @ObservationIgnored private var pendingRecoverySave: DispatchWorkItem?
    @ObservationIgnored private var isRestoringRecovery = false

    init(windowID: UUID = UUID(), coordinator: DocumentCoordinator? = nil) {
        self.windowID = windowID
        self.coordinator = coordinator
    }

    deinit {
        // A delayed recovery write must not outlive a test/application store and write after its
        // owner has gone away.
        pendingRecoverySave?.cancel()
    }

    private(set) var documents: [Document] = []
    var activeID: UUID? {
        didSet {
            guard activeID != oldValue else { return }
            if let oldValue {
                documents.first(where: { $0.id == oldValue })?.stopWatching()
            }
            activeDocument?.reloadFromDiskIfChanged()
            activeDocument?.reconcileActiveHeadingWithCurrentContent()
            refreshWindowAppearance()
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
    func open(url: URL, activate: Bool = true) -> Document {
        if let existing = documents.first(where: { $0.fileURL == url }) {
            if activate { activeID = existing.id }
            return existing
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let doc = Document(fileURL: url, rawText: text)
        observe(doc)
        doc.headings = HeadingParser.parseHeadings(in: text)
        documents.append(doc)
        if activate { activeID = doc.id }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        return doc
    }

    /// Opens a URL in this store without consulting another window. The coordinator is the
    /// only app-level caller, so global uniqueness remains centralized there.
    @discardableResult
    func openLocally(url: URL, activate: Bool = true) -> Document {
        open(url: url, activate: activate)
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
        refreshWatcher(for: document)
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
        refreshWatcher(for: document)
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
            refreshWatcher(for: document)
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
            refreshWatcher(for: document)
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
        refreshWatcher(for: document)
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
            document.clearUndoHistory()
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

    // internal so tab drop delegates and file-watch teardown can call it
    func removeDocument(id: UUID) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[idx].onStateChange = nil
        documents[idx].stopWatching()
        documents.remove(at: idx)
        if activeID == id {
            activeID = documents.isEmpty ? nil : documents[min(idx, documents.count - 1)].id
        }
        scheduleRecoverySave()
    }

    /// Removes a document for a move/detach. The destination restarts the watcher when it adopts
    /// the document as its active tab; editor state and recovery observation stay with the object.
    @discardableResult
    func removeForTransfer(id: UUID) -> Document? {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return nil }
        let document = documents.remove(at: idx)
        document.stopWatching()
        if activeID == id {
            activeID = documents.isEmpty ? nil : documents[min(idx, documents.count - 1)].id
        }
        scheduleRecoverySave()
        return document
    }

    func insertDocument(_ document: Document, at index: Int) {
        let clamped = max(0, min(index, documents.count))
        observe(document)
        documents.insert(document, at: clamped)
        activeID = document.id
    }

    func detachToNewWindow(_ document: Document) {
        coordinator?.detach(documentID: document.id, from: windowID)
    }

    func closeWindow() {
        coordinator?.closeWindow(id: windowID)
    }

    // MARK: - Tab order

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
        coordinator?.restorePersistedSession()
    }

    /// Installs coordinator-owned recovery state into this store without creating a second
    /// recovery writer.
    func restore(documents restoredDocuments: [Document], activeID restoredActiveID: UUID?) {
        guard self.documents.isEmpty else { return }

        isRestoringRecovery = true
        defer {
            isRestoringRecovery = false
            scheduleRecoverySave()
        }

        documents = restoredDocuments
        restoredDocuments.forEach(observe)
        if let activeID = restoredActiveID,
           restoredDocuments.contains(where: { $0.id == activeID }) {
            self.activeID = activeID
        } else {
            self.activeID = restoredDocuments.first?.id
        }
    }

    func persistSession() {
        coordinator?.persistSession()
    }

    func saveIgnoringErrors(_ document: Document) {
        try? save(document)
    }

    // MARK: - Proxy icon + dirty close button

    func refreshWindowAppearance() {
        guard let document = activeDocument else {
            managedWindow?.representedURL = nil
            managedWindow?.title = "Markfops"
            managedWindow?.isDocumentEdited = false
            return
        }
        updateProxyIcon(for: document)
    }

    private func updateProxyIcon(for document: Document) {
        managedWindow?.representedURL = document.fileURL
        managedWindow?.title = document.displayTitle
        managedWindow?.isDocumentEdited = document.isDirty
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

    /// Shows an NSAlert as a sheet on this store's registered document window.
    private func showAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = managedWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func presentError(_ error: Error) {
        if let window = managedWindow {
            NSAlert(error: error).beginSheetModal(for: window)
        } else {
            NSAlert(error: error).runModal()
        }
    }

    private func observe(_ document: Document) {
        document.onStateChange = { [weak self] changedDocument in
            guard let self else { return }
            if self.activeID == changedDocument.id {
                self.refreshWindowAppearance()
            }
            self.scheduleRecoverySave()
        }
    }

    private func refreshWatcher(for document: Document) {
        if activeID == document.id {
            document.startWatching()
        } else {
            document.stopWatching()
        }
    }

    private func scheduleRecoverySave() {
        guard !isRestoringRecovery else { return }
        guard coordinator != nil else { return }
        pendingRecoverySave?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.coordinator?.persistSession()
        }
        pendingRecoverySave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }
}

/// One live document scene. A document is owned by exactly one session at a time; the
/// coordinator, rather than SwiftUI view lifetime, owns the session's store.
final class DocumentWindowSession {
    let id: UUID
    let store: DocumentStore
    weak var window: NSWindow?

    init(id: UUID, coordinator: DocumentCoordinator) {
        self.id = id
        self.store = DocumentStore(windowID: id, coordinator: coordinator)
    }
}

/// App-lifetime registry for document windows and documents.
///
/// This is deliberately the only owner of global open routing and recovery writes. Stores keep
/// document-local editing operations, while this object handles ownership-changing operations.
@Observable
final class DocumentCoordinator: NSObject, NSWindowDelegate {
    static let documentWindowIdentifierPrefix = "Markfops.DocumentWindow."

    @ObservationIgnored private(set) var sessions: [UUID: DocumentWindowSession] = [:]
    @ObservationIgnored private(set) var lastActiveWindowID: UUID?

    @ObservationIgnored private let recoveryStore: RecoveryStore
    @ObservationIgnored private var didLoadRecovery = false
    @ObservationIgnored private var pendingURLs: [URL] = []
    @ObservationIgnored private var pendingPresentationIDs: [UUID] = []
    @ObservationIgnored private var reservedSceneIDs: Set<UUID> = []
    @ObservationIgnored private var openWindowRequest: ((UUID) -> Void)?
    @ObservationIgnored private var closingWindowIDs: Set<UUID> = []
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []

    init(recoveryDirectoryURL: URL? = nil) {
        self.recoveryStore = RecoveryStore(directoryURL: recoveryDirectoryURL)
        super.init()
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.touch(window: window)
        })
        notificationTokens.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.deregister(window: window)
        })
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func session(for id: UUID, create: Bool = true) -> DocumentWindowSession? {
        if let session = sessions[id] { return session }
        guard create else { return nil }
        let session = DocumentWindowSession(id: id, coordinator: self)
        sessions[id] = session
        return session
    }

    func store(for id: UUID) -> DocumentStore {
        session(for: id)!.store
    }

    /// Claims one restored session for a value-less initial WindowGroup scene, or creates a fresh
    /// session for a normal launch. A claim happens before AppKit supplies the NSWindow, preventing
    /// simultaneous external-open scenes from binding to the same tab catalog.
    func bootstrapWindowID() -> UUID {
        if let id = sessions.keys.first(where: {
            sessions[$0]?.window == nil && !reservedSceneIDs.contains($0)
        }) {
            reservedSceneIDs.insert(id)
            return id
        }
        let id = UUID()
        _ = session(for: id)
        reservedSceneIDs.insert(id)
        return id
    }

    func install(openWindow: @escaping (UUID) -> Void) {
        openWindowRequest = openWindow
        presentPendingScenes()
        flushPendingURLs()
    }

    func registerWindow(id: UUID, window: NSWindow) {
        guard let session = session(for: id) else { return }
        reservedSceneIDs.remove(id)
        let isNewWindowRegistration = session.window !== window
        session.window = window
        session.store.managedWindow = window
        window.identifier = NSUserInterfaceItemIdentifier(Self.documentWindowIdentifierPrefix + id.uuidString)
        window.delegate = self
        window.representedURL = session.store.activeDocument?.fileURL
        window.title = session.store.activeDocument?.displayTitle ?? "Markfops"
        window.isDocumentEdited = session.store.activeDocument?.isDirty ?? false
        session.store.refreshWindowAppearance()
        // SwiftUI may update the accessor repeatedly during unrelated view refreshes. Only a
        // genuinely new, already-key window gets an initial MRU touch; subsequent ordering is
        // owned by NSWindow.didBecomeKeyNotification.
        if isNewWindowRegistration, window.isKeyWindow {
            touch(sessionID: id)
        }
        flushPendingURLs()
    }

    func touch(window: NSWindow) {
        guard let id = sessions.first(where: { $0.value.window === window })?.key else { return }
        touch(sessionID: id)
    }

    func touch(sessionID: UUID) {
        guard sessions[sessionID] != nil else { return }
        lastActiveWindowID = sessionID
    }

    // MARK: - Global open routing

    @discardableResult
    func open(url: URL, preferredWindowID: UUID? = nil) -> Document? {
        let normalized = Self.normalizedFileURL(url)
        if let owner = owner(of: normalized) {
            focus(sessionID: owner.id, documentID: owner.document.id)
            return owner.document
        }

        guard let target = preferredSession(preferredWindowID) else {
            pendingURLs.append(normalized)
            presentPendingScenes()
            return nil
        }
        let document = target.store.openLocally(url: normalized)
        focus(sessionID: target.id, documentID: document.id)
        return document
    }

    func open(urls: [URL], preferredWindowID: UUID? = nil) {
        guard !urls.isEmpty else { return }
        let normalizedURLs = urls.map(Self.normalizedFileURL)
        guard let target = preferredSession(preferredWindowID) else {
            pendingURLs.append(contentsOf: normalizedURLs)
            presentPendingScenes()
            return
        }

        var finalSelection: (sessionID: UUID, documentID: UUID)?
        for url in normalizedURLs {
            if let owner = owner(of: url) {
                finalSelection = (owner.id, owner.document.id)
            } else {
                let document = target.store.openLocally(url: url, activate: false)
                finalSelection = (target.id, document.id)
            }
        }
        if let finalSelection {
            focus(
                sessionID: finalSelection.sessionID,
                documentID: finalSelection.documentID
            )
        }
    }

    private func preferredSession(_ preferredID: UUID?) -> DocumentWindowSession? {
        if let preferredID, let preferred = sessions[preferredID] { return preferred }
        if let lastActiveWindowID, let last = sessions[lastActiveWindowID] { return last }
        return sessions.values.first
    }

    private func owner(of url: URL) -> (id: UUID, document: Document)? {
        for (id, session) in sessions {
            if let document = session.store.documents.first(where: {
                guard let existingURL = $0.fileURL else { return false }
                return Self.normalizedFileURL(existingURL) == url
            }) {
                return (id, document)
            }
        }
        return nil
    }

    func focus(sessionID: UUID, documentID: UUID? = nil) {
        guard let session = sessions[sessionID] else { return }
        if let documentID { session.store.activeID = documentID }
        session.store.refreshWindowAppearance()
        touch(sessionID: sessionID)
        guard let window = session.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - New windows and transfers

    @discardableResult
    func newWindow(withNewDocument: Bool = true) -> DocumentWindowSession {
        let id = UUID()
        let session = self.session(for: id)!
        if withNewDocument { session.store.newDocument() }
        requestScene(id: id)
        return session
    }

    func detach(documentID: UUID, from sourceID: UUID) {
        let destination = newWindow(withNewDocument: false)
        move(documentID: documentID, from: sourceID, to: destination.id, at: 0)
        focus(sessionID: destination.id, documentID: documentID)
    }

    func move(documentID: UUID, from sourceID: UUID, to destinationID: UUID, at index: Int? = nil) {
        guard sourceID != destinationID,
              let source = sessions[sourceID],
              let destination = sessions[destinationID],
              let document = source.store.removeForTransfer(id: documentID)
        else {
            if sourceID == destinationID, let store = sessions[sourceID]?.store,
               let from = store.documents.firstIndex(where: { $0.id == documentID }),
               let index {
                store.moveTab(fromOffsets: IndexSet(integer: from), toOffset: index)
            }
            return
        }
        destination.store.insertDocument(document, at: index ?? destination.store.documents.count)
        focus(sessionID: destinationID, documentID: documentID)
        if source.store.documents.isEmpty { closeEmptySession(sourceID) }
        persistSession()
    }

    private func requestScene(id: UUID) {
        guard !pendingPresentationIDs.contains(id) else { return }
        pendingPresentationIDs.append(id)
        presentPendingScenes()
    }

    private func presentPendingScenes() {
        guard let openWindowRequest else { return }
        let ids = pendingPresentationIDs
        pendingPresentationIDs.removeAll()
        ids.forEach(openWindowRequest)
    }

    // MARK: - Recovery

    func restorePersistedSession() {
        loadRecoveryIfNeeded()
        presentPendingScenes()
    }

    private func loadRecoveryIfNeeded() {
        guard !didLoadRecovery else { return }
        didLoadRecovery = true
        guard let snapshot = recoveryStore.load() else {
            if sessions.isEmpty { _ = session(for: UUID()) }
            return
        }

        var seenIDs = Set<UUID>()
        var seenURLs = Set<URL>()
        let usesLegacyTOCDefault = snapshot.tocExpansionDefaultsVersion
            < RecoverySnapshot.currentTOCExpansionDefaultsVersion
        for windowSnapshot in snapshot.windows {
            let session = self.session(for: windowSnapshot.id)!
            var restored: [Document] = []
            for documentSnapshot in windowSnapshot.documents {
                guard !seenIDs.contains(documentSnapshot.id) else { continue }
                let url = documentSnapshot.fileURLString.flatMap(URL.init(string:)).map(Self.normalizedFileURL)
                if let url, seenURLs.contains(url) { continue }
                guard let document = Self.restoreDocument(
                    from: documentSnapshot,
                    usesLegacyTOCDefault: usesLegacyTOCDefault
                ) else { continue }
                seenIDs.insert(document.id)
                if let url { seenURLs.insert(url) }
                restored.append(document)
            }
            session.store.restore(documents: restored, activeID: windowSnapshot.activeID)
        }

        if sessions.isEmpty { _ = session(for: UUID()) }
        lastActiveWindowID = snapshot.activeWindowID ?? sessions.keys.first
        // The first WindowGroup scene consumes the first value-less session; all additional
        // restored sessions are explicitly opened by their stable UUID values.
        pendingPresentationIDs = sessions.keys.filter { sessions[$0]?.window == nil }.dropFirst().map { $0 }
    }

    func persistSession() {
        loadRecoveryIfNeeded()
        let windows = sessions.values.compactMap { session -> RecoveryWindowSnapshot? in
            let docs = session.store.documents.compactMap(Self.snapshot(for:))
            guard !docs.isEmpty else { return nil }
            return RecoveryWindowSnapshot(id: session.id, documents: docs, activeID: session.store.activeID)
        }
        let snapshot = RecoverySnapshot(windows: windows, activeWindowID: lastActiveWindowID)
        recoveryStore.save(snapshot)
        CrashRecoveryInfoReporter.shared.update(
            recoveryStore.status(for: snapshot, activeDocumentTitle: sessions[lastActiveWindowID ?? UUID()]?.store.activeDocument?.displayTitle).crashLogMessage
        )
    }

    private func flushPendingURLs() {
        guard !pendingURLs.isEmpty, preferredSession(nil) != nil else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        open(urls: urls)
    }

    // MARK: - Closing

    func closeWindow(id: UUID) {
        guard let session = sessions[id] else { return }
        let dirty = session.store.documents.filter(\.isDirty)
        if dirty.isEmpty {
            closeWindowImmediately(id: id)
            return
        }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("You have unsaved changes", comment: "Close window alert title")
        alert.informativeText = dirty.map(\.displayTitle).joined(separator: ", ")
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Save button"))
        alert.addButton(withTitle: NSLocalizedString("Don't Save", comment: "Discard button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        if let window = session.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                self?.finishCloseWindow(id: id, dirty: dirty, response: response)
            }
        } else {
            finishCloseWindow(id: id, dirty: dirty, response: alert.runModal())
        }
    }

    private func finishCloseWindow(id: UUID, dirty: [Document], response: NSApplication.ModalResponse) {
        switch response {
        case .alertFirstButtonReturn:
            guard let store = sessions[id]?.store else { return }
            dirty.forEach { try? store.save($0) }
            closeWindowImmediately(id: id)
        case .alertSecondButtonReturn:
            closeWindowImmediately(id: id)
        default:
            break
        }
    }

    private func closeWindowImmediately(id: UUID) {
        guard let session = sessions[id] else { return }
        closingWindowIDs.insert(id)
        if let window = session.window {
            window.performClose(nil)
        } else {
            deregister(sessionID: id)
        }
    }

    private func closeEmptySession(_ id: UUID) {
        guard sessions[id]?.store.documents.isEmpty == true else { return }
        closeWindowImmediately(id: id)
    }

    func reviewUnsavedForQuit(completion: @escaping (Bool) -> Void) {
        let dirty = sessions.values.flatMap { $0.store.documents }.filter(\.isDirty)
        guard !dirty.isEmpty else { completion(true); return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("You have unsaved changes", comment: "Quit alert title")
        alert.informativeText = dirty.map(\.displayTitle).joined(separator: ", ")
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Save button"))
        alert.addButton(withTitle: NSLocalizedString("Quit Anyway", comment: "Quit without saving"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        let window = sessions[lastActiveWindowID ?? UUID()]?.window
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { completion(false); return }
            switch response {
            case .alertFirstButtonReturn:
                dirty.forEach { document in
                    self.sessions.values.first(where: { $0.store.documents.contains(document) })?.store.saveIgnoringErrors(document)
                }
                completion(true)
            case .alertSecondButtonReturn: completion(true)
            default: completion(false)
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: finish) }
        else { finish(alert.runModal()) }
    }

    func windowShouldClose(_ window: NSWindow) -> Bool {
        guard let id = sessions.first(where: { $0.value.window === window })?.key else { return true }
        if closingWindowIDs.remove(id) != nil { return true }
        closeWindow(id: id)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        deregister(window: window)
    }

    private func deregister(window: NSWindow) {
        guard let id = sessions.first(where: { $0.value.window === window })?.key else { return }
        deregister(sessionID: id)
    }

    private func deregister(sessionID id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.store.managedWindow = nil
        session.store.documents.forEach { $0.stopWatching(); $0.onStateChange = nil }
        if lastActiveWindowID == id { lastActiveWindowID = sessions.keys.first }
        persistSession()
    }

    static func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func snapshot(for document: Document) -> RecoveryDocumentSnapshot? {
        let fileURLString = document.fileURL?.absoluteString
        let shouldEmbedDraft = document.isDirty || document.fileURL == nil
        let rawText = shouldEmbedDraft ? document.rawText : nil
        let savedText = shouldEmbedDraft ? document.savedText : nil
        guard fileURLString != nil || !(rawText ?? "").isEmpty || document.isDirty else { return nil }
        return RecoveryDocumentSnapshot(
            id: document.id, displayTitle: document.displayTitle, fileURLString: fileURLString,
            rawText: rawText, savedText: savedText, isDirty: document.isDirty,
            mode: document.mode.rawValue, scrollRatio: document.scrollRatio,
            activeHeadingID: document.activeHeadingID, isTOCExpanded: document.isTOCExpanded,
            collapsedHeadingIDs: document.collapsedHeadingIDs
        )
    }

    private static func restoreDocument(
        from snapshot: RecoveryDocumentSnapshot,
        usesLegacyTOCDefault: Bool = false
    ) -> Document? {
        let fileURL = snapshot.fileURLString.flatMap(URL.init(string:))
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            let diskText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let rawText = snapshot.isDirty ? (snapshot.rawText ?? diskText) : diskText
            let document = Document(id: snapshot.id, fileURL: fileURL, rawText: rawText)
            document.savedText = snapshot.savedText ?? diskText
            document.isDirty = snapshot.isDirty && rawText != document.savedText
            document.mode = EditMode(rawValue: snapshot.mode) ?? .edit
            document.scrollRatio = snapshot.scrollRatio
            document.activeHeadingID = snapshot.activeHeadingID
            document.isTOCExpanded = usesLegacyTOCDefault ? true : snapshot.isTOCExpanded
            document.collapsedHeadingIDs = snapshot.collapsedHeadingIDs
            document.headings = HeadingParser.parseHeadings(in: rawText)
            return document
        }
        guard let rawText = snapshot.rawText, !rawText.isEmpty || snapshot.isDirty else { return nil }
        let document = Document(id: snapshot.id, rawText: rawText)
        document.savedText = snapshot.savedText ?? ""
        document.isDirty = true
        document.mode = EditMode(rawValue: snapshot.mode) ?? .edit
        document.scrollRatio = snapshot.scrollRatio
        document.activeHeadingID = snapshot.activeHeadingID
        document.isTOCExpanded = usesLegacyTOCDefault ? true : snapshot.isTOCExpanded
        document.collapsedHeadingIDs = snapshot.collapsedHeadingIDs
        document.headings = HeadingParser.parseHeadings(in: rawText)
        return document
    }
}

struct RecoverySnapshot: Codable {
    static let currentTOCExpansionDefaultsVersion = 1

    var windows: [RecoveryWindowSnapshot]
    var activeWindowID: UUID?
    var tocExpansionDefaultsVersion: Int

    /// Legacy flat fields are accepted for migration from the single-window snapshot.
    init(windows: [RecoveryWindowSnapshot], activeWindowID: UUID?) {
        self.windows = windows
        self.activeWindowID = activeWindowID
        self.tocExpansionDefaultsVersion = Self.currentTOCExpansionDefaultsVersion
    }

    init(documents: [RecoveryDocumentSnapshot], activeID: UUID?) {
        let id = UUID()
        self.windows = [RecoveryWindowSnapshot(id: id, documents: documents, activeID: activeID)]
        self.activeWindowID = id
        self.tocExpansionDefaultsVersion = Self.currentTOCExpansionDefaultsVersion
    }

    enum CodingKeys: String, CodingKey {
        case windows, activeWindowID, documents, activeID, tocExpansionDefaultsVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let windows = try values.decodeIfPresent([RecoveryWindowSnapshot].self, forKey: .windows) {
            self.windows = windows
            self.activeWindowID = try values.decodeIfPresent(UUID.self, forKey: .activeWindowID)
        } else {
            let documents = try values.decodeIfPresent([RecoveryDocumentSnapshot].self, forKey: .documents) ?? []
            let activeID = try values.decodeIfPresent(UUID.self, forKey: .activeID)
            let id = UUID()
            self.windows = [RecoveryWindowSnapshot(id: id, documents: documents, activeID: activeID)]
            self.activeWindowID = id
        }
        self.tocExpansionDefaultsVersion = try values.decodeIfPresent(
            Int.self,
            forKey: .tocExpansionDefaultsVersion
        ) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(windows, forKey: .windows)
        try values.encodeIfPresent(activeWindowID, forKey: .activeWindowID)
        try values.encode(tocExpansionDefaultsVersion, forKey: .tocExpansionDefaultsVersion)
    }

    var documents: [RecoveryDocumentSnapshot] { windows.flatMap(\.documents) }
    var activeID: UUID? {
        guard let window = windows.first(where: { $0.id == activeWindowID }) else { return nil }
        return window.activeID
    }
}

struct RecoveryWindowSnapshot: Codable {
    var id: UUID
    var documents: [RecoveryDocumentSnapshot]
    var activeID: UUID?
}

struct RecoveryDocumentSnapshot: Codable {
    var id: UUID
    var displayTitle: String
    var fileURLString: String?
    var rawText: String?
    var savedText: String?
    var isDirty: Bool
    var mode: String = EditMode.edit.rawValue
    var scrollRatio: Double = 0
    var activeHeadingID: String?
    var isTOCExpanded: Bool = true
    var collapsedHeadingIDs: Set<String> = []

    enum CodingKeys: String, CodingKey {
        case id, displayTitle, fileURLString, rawText, savedText, isDirty
        case mode, scrollRatio, activeHeadingID, isTOCExpanded, collapsedHeadingIDs
    }

    init(id: UUID, displayTitle: String, fileURLString: String?, rawText: String?, savedText: String?,
         isDirty: Bool, mode: String = EditMode.edit.rawValue, scrollRatio: Double = 0,
         activeHeadingID: String? = nil, isTOCExpanded: Bool = true,
         collapsedHeadingIDs: Set<String> = []) {
        self.id = id
        self.displayTitle = displayTitle
        self.fileURLString = fileURLString
        self.rawText = rawText
        self.savedText = savedText
        self.isDirty = isDirty
        self.mode = mode
        self.scrollRatio = scrollRatio
        self.activeHeadingID = activeHeadingID
        self.isTOCExpanded = isTOCExpanded
        self.collapsedHeadingIDs = collapsedHeadingIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        displayTitle = try values.decode(String.self, forKey: .displayTitle)
        fileURLString = try values.decodeIfPresent(String.self, forKey: .fileURLString)
        rawText = try values.decodeIfPresent(String.self, forKey: .rawText)
        savedText = try values.decodeIfPresent(String.self, forKey: .savedText)
        isDirty = try values.decode(Bool.self, forKey: .isDirty)
        mode = try values.decodeIfPresent(String.self, forKey: .mode) ?? EditMode.edit.rawValue
        scrollRatio = try values.decodeIfPresent(Double.self, forKey: .scrollRatio) ?? 0
        activeHeadingID = try values.decodeIfPresent(String.self, forKey: .activeHeadingID)
        isTOCExpanded = try values.decodeIfPresent(Bool.self, forKey: .isTOCExpanded) ?? true
        collapsedHeadingIDs = try values.decodeIfPresent(Set<String>.self, forKey: .collapsedHeadingIDs) ?? []
    }
}

private struct RecoveryStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let configuredDirectoryURL: URL?

    init(directoryURL: URL? = nil) {
        self.configuredDirectoryURL = directoryURL
    }

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
        if let configuredDirectoryURL { return configuredDirectoryURL }
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
