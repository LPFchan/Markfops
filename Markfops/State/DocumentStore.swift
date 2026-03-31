import AppKit
import Observation

@Observable
final class DocumentStore {
    private(set) var documents: [Document] = []
    var activeID: UUID? {
        didSet {
            guard activeID != oldValue else { return }
            activeDocument?.reloadFromDiskIfClean(restartWatching: true)
            activeDocument?.reconcileActiveHeadingWithCurrentContent()
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
        documents[idx].stopWatching()
        documents.remove(at: idx)
        if activeID == id {
            activeID = documents.isEmpty ? nil : documents[min(idx, documents.count - 1)].id
        }
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
        documents.remove(at: idx)
        if activeID == document.id {
            activeID = documents.isEmpty ? nil : documents[min(idx, documents.count - 1)].id
        }

        let newStore = DocumentStore()
        newStore.documents = [document]
        newStore.activeID  = document.id

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
        documents.insert(document, at: clamped)
        activeID = document.id
    }

    func moveTab(fromOffsets: IndexSet, toOffset: Int) {
        documents.move(fromOffsets: fromOffsets, toOffset: toOffset)
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
}

// MARK: - FocusedValues

import SwiftUI

struct DocumentStoreFocusKey: FocusedValueKey {
    typealias Value = DocumentStore
}

struct SidebarVisibilityKey: FocusedValueKey {
    typealias Value = Binding<NavigationSplitViewVisibility>
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
}
