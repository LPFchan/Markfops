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
        // If already open, just activate it
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

    func close(id: UUID) {
        guard let doc = documents.first(where: { $0.id == id }) else { return }

        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Save changes to \"\(doc.displayTitle)\"?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                try? save(doc)
            case .alertSecondButtonReturn:
                break
            default:
                return
            }
        }

        removeDocument(id: id)
    }

    private func removeDocument(id: UUID) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents.remove(at: idx)

        if activeID == id {
            if documents.isEmpty {
                activeID = nil
            } else {
                let newIdx = min(idx, documents.count - 1)
                activeID = documents[newIdx].id
            }
        }
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
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Unsaved documents: \(names)"
        alert.addButton(withTitle: "Review Unsaved…")
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")

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
