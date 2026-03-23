import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(DocumentStore.self) private var store
    var onTOCTap: (HeadingNode) -> Void
    /// Passed from ContentView so the toolbar + button hides when the sidebar itself is hidden (compact mode).
    @Binding var columnVisibility: NavigationSplitViewVisibility

    /// Per-document TOC visibility — collapses on deselect, restores on reselect.
    @State private var tocVisible: [UUID: Bool] = [:]
    /// Index before which the accent insertion line is shown during a cross-window drag.
    @State private var dropInsertionIndex: Int? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(Array(store.documents.enumerated()), id: \.element.id) { i, document in
                        Section {
                            // Collapse TOC while this pill is being dragged
                            let isVisible = (tocVisible[document.id] ?? false)
                                && TabDragState.shared.draggingDocumentID != document.id
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
                            sectionHeader(document: document, index: i)
                        }  // Section
                    }  // ForEach
                }  // LazyVStack
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
            // Only show the + button when the sidebar column is actually visible.
            // In compact mode the pill bar already has its own + button.
            if columnVisibility != .detailOnly {
                ToolbarItemGroup(placement: .automatic) {
                    Spacer()
                    Button(action: { store.newDocument() }) {
                        Image(systemName: "plus")
                    }
                    .help("New Document  ⌘N")
                }
            }
        }
        .onAppear {
            for doc in store.documents {
                tocVisible[doc.id] = doc.isTOCExpanded && doc.id == store.activeID
            }
        }
    }

    // MARK: - Section header (extracted to help Swift type-checker)

    @ViewBuilder
    private func sectionHeader(document: Document, index: Int) -> some View {
        let isDragging    = TabDragState.shared.draggingDocumentID == document.id
        let isAnyDragging = TabDragState.shared.draggingDocumentID != nil
        let translation   = TabDragState.shared.dragTranslation
        // In the sidebar (vertical list), horizontal drag = detach; vertical drag = reorder.
        let inDetachZone  = isDragging && abs(translation.width) > 60

        VStack(spacing: 0) {
            if dropInsertionIndex == index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 1.5)
                    .padding(.horizontal, 14)
                    .transition(.opacity)
            }
            SidebarTabRowView(
                document: document,
                isActive: store.activeID == document.id,
                isTOCVisible: Binding(
                    get: { tocVisible[document.id] ?? false },
                    set: { tocVisible[document.id] = $0 }
                ),
                onSelect: { store.activeID = document.id },
                onClose: { store.close(id: document.id) },
                isInDetachZone: inDetachZone
            )
            .id(document.id)
            .padding(.horizontal, 6)
            .opacity(isAnyDragging && !isDragging ? 0.45 : 1.0)
            .scaleEffect(
                inDetachZone ? 1.04 : (isDragging ? 1.03 : (isAnyDragging ? 0.97 : 1.0)),
                anchor: .trailing
            )
            .shadow(
                color: isDragging ? .black.opacity(0.25) : .clear,
                radius: inDetachZone ? 12 : (isDragging ? 8 : 0),
                y: isDragging ? 4 : 0
            )
            .offset(
                x: isDragging ? translation.width : 0,
                y: isDragging ? translation.height : 0
            )
            .zIndex(isDragging ? 100 : 0)
            .animation(.spring(duration: 0.22), value: isDragging)
            .animation(.spring(duration: 0.18), value: inDetachZone)
            .animation(.easeOut(duration: 0.15), value: isAnyDragging)
            .onDrag { makeDragProvider(for: document) }
            .onDrop(of: [.data],
                    delegate: DocumentDropDelegate(
                        targetDocument: document,
                        store: store,
                        onInsertionIndexChange: { idx in
                            withAnimation(.easeOut(duration: 0.12)) {
                                dropInsertionIndex = idx
                            }
                        }
                    ))
        }
    }

    private func makeDragProvider(for document: Document) -> NSItemProvider {
        TabDragState.shared.begin(documentID: document.id, from: store)

        var upMonitor:   Any?
        var moveMonitor: Any?

        // Global monitors (not local) so events are received during system drag sessions.
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { event in
            DispatchQueue.main.async {
                TabDragState.shared.dragTranslation.width  += event.deltaX
                TabDragState.shared.dragTranslation.height -= event.deltaY
            }
        }

        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            if let m = upMonitor   { NSEvent.removeMonitor(m) }
            if let m = moveMonitor { NSEvent.removeMonitor(m) }
            upMonitor = nil; moveMonitor = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard TabDragState.shared.draggingDocumentID == document.id else { return }
                let shouldDetach = TabDragState.shared.wasInDetachZone
                TabDragState.shared.reset()
                if shouldDetach { store.detachToNewWindow(document) }
            }
        }

        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.data.identifier,
            visibility: .all
        ) { completion in
            let data = document.id.uuidString.data(using: .utf8) ?? Data()
            completion(data, nil)
            return nil
        }
        return provider
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
