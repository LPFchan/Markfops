import SwiftUI

struct SidebarView: View {
    @Environment(DocumentStore.self) private var store
    var onTOCTap: (HeadingNode) -> Void

    /// Per-document TOC visibility — collapses on deselect, restores on reselect.
    @State private var tocVisible: [UUID: Bool] = [:]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(store.documents) { document in
                        Section {
                            // Collapse TOC while this pill is being dragged
                            let isVisible = (tocVisible[document.id] ?? false)
                                && store.draggingDocumentID != document.id
                            if isVisible && !document.headings.isEmpty {
                                ForEach(visibleHeadings(for: document), id: \.id) { heading in
                                    TOCItemView(
                                        heading: heading,
                                        isHighlighted: false,
                                        isCollapsible: headingHasChildren(heading, in: document),
                                        isCollapsed: document.collapsedHeadingIDs.contains(heading.id),
                                        onTap: {
                                            if store.activeID != document.id {
                                                store.activeID = document.id
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                    onTOCTap(heading)
                                                }
                                            } else {
                                                onTOCTap(heading)
                                            }
                                        },
                                        onToggleCollapse: {
                                            withAnimation(.spring(duration: 0.22)) {
                                                toggleCollapse(heading, in: document)
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 6)
                                    .padding(.bottom, 1)
                                }
                                .padding(.bottom, 4)
                            }
                        } header: {
                            SidebarTabRowView(
                                document: document,
                                isActive: store.activeID == document.id,
                                isTOCVisible: Binding(
                                    get: { tocVisible[document.id] ?? false },
                                    set: { tocVisible[document.id] = $0 }
                                ),
                                onSelect: { store.activeID = document.id },
                                onClose: { store.close(id: document.id) }
                            )
                            .id(document.id)
                            .padding(.horizontal, 6)
                            // ── Drag to reorder / drag to new window ──────────────────────
                            .onDrag {
                                store.draggingDocumentID = document.id

                                // Mouse-up monitor: if no onDrop accepted the drag, detach.
                                var monitor: Any?
                                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                                    if let m = monitor { NSEvent.removeMonitor(m) }
                                    monitor = nil
                                    // Give performDrop a tick to clear draggingDocumentID first
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        if store.draggingDocumentID == document.id {
                                            store.draggingDocumentID = nil
                                            store.detachToNewWindow(document)
                                        }
                                    }
                                    return event
                                }

                                return NSItemProvider(object: document.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text],
                                    delegate: DocumentDropDelegate(targetDocument: document,
                                                                   store: store))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: store.activeID) { oldID, newID in
                // Collapse outgoing document (persist its expanded intent first)
                if let old = oldID,
                   let doc = store.documents.first(where: { $0.id == old }) {
                    doc.isTOCExpanded = tocVisible[old] ?? false
                    withAnimation(.spring(duration: 0.22)) {
                        tocVisible[old] = false
                    }
                }
                // Restore incoming document's TOC
                if let new = newID,
                   let doc = store.documents.first(where: { $0.id == new }) {
                    withAnimation(.spring(duration: 0.22)) {
                        tocVisible[new] = doc.isTOCExpanded
                    }
                    // Scroll to reveal the document's header row
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(new, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Spacer()
                Button(action: { store.newDocument() }) {
                    Image(systemName: "plus")
                }
                .help("New Document  ⌘N")
            }
        }
        .onAppear {
            for doc in store.documents {
                tocVisible[doc.id] = doc.isTOCExpanded && doc.id == store.activeID
            }
        }
    }

    // MARK: - TOC helpers

    private func visibleHeadings(for document: Document) -> [HeadingNode] {
        let headings = document.headings.filter { $0.level > 1 }
        var result: [HeadingNode] = []
        var hiddenBelowLevel: Int? = nil

        for heading in headings {
            if let barrier = hiddenBelowLevel {
                if heading.level > barrier { continue }
                hiddenBelowLevel = nil
            }
            result.append(heading)
            if document.collapsedHeadingIDs.contains(heading.id) {
                hiddenBelowLevel = heading.level
            }
        }
        return result
    }

    private func headingHasChildren(_ heading: HeadingNode, in document: Document) -> Bool {
        let headings = document.headings.filter { $0.level > 1 }
        guard let idx = headings.firstIndex(where: { $0.id == heading.id }),
              idx + 1 < headings.count else { return false }
        return headings[idx + 1].level > heading.level
    }

    private func toggleCollapse(_ heading: HeadingNode, in document: Document) {
        if document.collapsedHeadingIDs.contains(heading.id) {
            document.collapsedHeadingIDs.remove(heading.id)
        } else {
            document.collapsedHeadingIDs.insert(heading.id)
        }
    }
}
