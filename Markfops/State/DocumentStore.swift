import AppKit
import Observation

@Observable
final class DocumentStore {
    private(set) var documents: [Document] = []
    var activeID: UUID?

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
        documents.append(doc)
        activeID = doc.id
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        return doc
    }

    func save(_ document: Document) throws {
        guard let url = document.fileURL else {
            try saveAs(document)
            return
        }
        try document.rawText.write(to: url, atomically: true, encoding: .utf8)
        document.isDirty = false
        updateProxyIcon(for: document)
    }

    func saveAs(_ document: Document) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = document.displayTitle + ".md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try document.rawText.write(to: url, atomically: true, encoding: .utf8)
        document.fileURL = url
        document.isDirty = false
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        updateProxyIcon(for: document)
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

    func rename(_ document: Document) {
        guard let currentURL = document.fileURL else {
            // Untitled — treat as Save As
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
    }

    // MARK: - Revert to Saved

    func revertToSaved(_ document: Document) {
        guard let url = document.fileURL else { return }
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Revert \"%@\" to saved version?", comment: "Revert alert title"), document.displayTitle)
        alert.informativeText = NSLocalizedString("Your unsaved changes will be lost.", comment: "Revert alert body")
        alert.addButton(withTitle: NSLocalizedString("Revert", comment: "Revert confirm button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        document.rawText = text
        document.isDirty = false
        document.headings = HeadingParser.parseHeadings(in: text)
    }

    // MARK: - Export as PDF

    func exportAsPDF(_ document: Document) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = document.displayTitle + ".pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Render via WKWebView off-screen
        let html = HTMLTemplate.currentPage(body: MarkdownRenderer.renderHTML(from: document.rawText))
        PDFExporter.export(html: html, to: url)
    }

    // MARK: - Close

    func close(id: UUID) {
        guard let doc = documents.first(where: { $0.id == id }) else { return }
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = String(format: NSLocalizedString("Save changes to \"%@\"?", comment: "Alert title when closing a tab with unsaved changes"), doc.displayTitle)
            alert.informativeText = NSLocalizedString("Your changes will be lost if you don't save them.", comment: "Alert body for unsaved changes")
            alert.addButton(withTitle: NSLocalizedString("Save", comment: "Save button"))
            alert.addButton(withTitle: NSLocalizedString("Don't Save", comment: "Discard button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: try? save(doc)
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        removeDocument(id: id)
    }

    private func removeDocument(id: UUID) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents.remove(at: idx)
        if activeID == id {
            activeID = documents.isEmpty ? nil : documents[min(idx, documents.count - 1)].id
        }
    }

    // MARK: - Tab order

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

    // MARK: - Proxy icon

    private func updateProxyIcon(for document: Document) {
        NSApp.mainWindow?.representedURL = document.fileURL
        NSApp.mainWindow?.title = document.displayTitle
    }

    // MARK: - Quit handling

    func checkUnsavedBeforeQuit() -> Bool {
        let dirtyDocs = documents.filter(\.isDirty)
        guard !dirtyDocs.isEmpty else { return true }
        let names = dirtyDocs.map(\.displayTitle).joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("You have unsaved changes", comment: "Quit alert title")
        alert.informativeText = String(format: NSLocalizedString("Unsaved documents: %@", comment: "Quit alert body listing document names"), names)
        alert.addButton(withTitle: NSLocalizedString("Review Unsaved\u{2026}", comment: "Save before quitting"))
        alert.addButton(withTitle: NSLocalizedString("Quit Anyway", comment: "Quit without saving"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel quit"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for doc in dirtyDocs { try? save(doc) }
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: - Helpers

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

// MARK: - FocusedValues

import SwiftUI

struct DocumentStoreFocusKey: FocusedValueKey {
    typealias Value = DocumentStore
}

extension FocusedValues {
    var documentStore: DocumentStore? {
        get { self[DocumentStoreFocusKey.self] }
        set { self[DocumentStoreFocusKey.self] = newValue }
    }
}
