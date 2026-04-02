import SwiftUI
import UniformTypeIdentifiers

// MARK: - Width measurement via preference (avoids layout loops from onGeometryChange)

private struct PillBarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Scrollable tab pill row — used as the toolbar's principal item in compact mode.
struct TabPillRowView: View {
    /// When set from the toolbar `GeometryReader`, pill widths follow the **alotted** principal
    /// width. Otherwise `ScrollView` content reports a huge intrinsic width and `NSToolbar` moves
    /// the whole principal item (or other controls) into the overflow `>>` menu instead of shrinking.
    var toolbarSlotWidth: CGFloat? = nil

    @Environment(DocumentStore.self) private var store
    @State private var dropInsertionIndex: Int? = nil
    /// Measured width when not using `toolbarSlotWidth` (e.g. standalone `HorizontalTabBarView`).
    @State private var availableWidth: CGFloat = 600

    private var widthForLayout: CGFloat {
        if let slot = toolbarSlotWidth, slot > 0 { return slot }
        return max(availableWidth, 1)
    }

    // MARK: - Dynamic pill width
    //
    // Divides available space equally across all pills. Floor is kept low so when the window is
    // narrow, pills shrink (and scroll) instead of the system toolbar overflowing the sidebar or
    // mode controls into the >> menu.
    private var pillWidth: CGFloat {
        let buttonW: CGFloat = 36 + 8   // + button + its trailing padding
        let leadPad: CGFloat = 8        // .padding(.leading, 8) on the scroll content
        let spacing: CGFloat = 4
        let count = max(1, CGFloat(store.documents.count))
        let forAllPills = widthForLayout - buttonW - leadPad - spacing * (count - 1)
        // Down to ~26pt: favicon-only tabs (see `DocumentTabView.isIconOnly`).
        return max(26, min(200, forAllPills / count))
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(store.documents.enumerated()), id: \.element.id) { i, document in
                            pillCell(document: document, index: i)
                        }

                        // Invisible drop zone after the last pill (rightmost gap).
                        Color.clear
                            .frame(width: 8, height: 32)
                            .onDrop(of: [TabDragState.documentDragType],
                                    delegate: TrailingDropDelegate(
                                        store: store,
                                        onInsertionIndexChange: { idx in
                                            withAnimation(.spring(duration: 0.15)) {
                                                dropInsertionIndex = idx
                                            }
                                        }
                                    ))

                        if dropInsertionIndex == store.documents.count {
                            insertionIndicator
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 5)
                }
                // Fill the HStack width so the strip does not inherit the scroll content's ideal width.
                .frame(maxWidth: .infinity)
                // Gradient fade on both edges to show there's more to scroll.
                .mask(alignment: .center) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .black, location: 0.04),
                            .init(color: .black, location: 0.93),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
                .onChange(of: store.activeID) { _, newID in
                    if let id = newID { withAnimation(.spring(duration: 0.22)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }

            // + button lives outside the scroll view so it's always visible.
            Button(action: { store.newDocument() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(NSColor.quaternaryLabelColor).opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("New Tab  ⌘T")
        }
        .frame(minWidth: 0)
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: toolbarSlotWidth != nil ? ToolbarMetrics.compactPillRowHeight : nil)
        // Measure width when not driven by the toolbar slot (standalone bar).
        .background(
            Group {
                if toolbarSlotWidth == nil {
                    GeometryReader { geo in
                        Color.clear.preference(key: PillBarWidthKey.self, value: geo.size.width)
                    }
                }
            }
        )
        .onPreferenceChange(PillBarWidthKey.self) { w in
            guard toolbarSlotWidth == nil, w > 10 else { return }
            availableWidth = w
        }
    }

    // MARK: - Pill cell

    @ViewBuilder
    private func pillCell(document: Document, index: Int) -> some View {
        let isDragging    = TabDragState.shared.draggingDocumentID == document.id
        let isAnyDragging = TabDragState.shared.draggingDocumentID != nil
        let translation   = TabDragState.shared.dragTranslation
        let inDetachZone  = isDragging && abs(translation.height) > 60

        if dropInsertionIndex == index { insertionIndicator }

        DocumentTabView(
            document: document,
            isActive: store.activeID == document.id,
            onSelect: { store.activeID = document.id },
            onClose: { store.close(id: document.id) },
            isInDetachZone: inDetachZone,
            pillWidth: pillWidth
        )
        .id(document.id)
        // Dragging pill becomes a ghost in-place; the system drag image follows the cursor.
        // No offset, no shadow, no zIndex boost — prevents the "two things moving" clutter.
        .opacity(isDragging ? 0.3 : (isAnyDragging ? 0.45 : 1.0))
        .scaleEffect(isDragging ? 0.92 : (isAnyDragging ? 0.96 : 1.0), anchor: .center)
        // Animate pill width changes as tabs open/close.
        .animation(.spring(duration: 0.28), value: pillWidth)
        .animation(.spring(duration: 0.22), value: isDragging)
        .animation(.spring(duration: 0.18), value: inDetachZone)
        .animation(.spring(duration: 0.15), value: isAnyDragging)
        // Track detach zone entry directly here so wasInDetachZone is set even when
        // DocumentTabView doesn't re-render (the @Observable dependency is in pillCell).
        .onChange(of: inDetachZone) { _, inZone in
            if inZone { TabDragState.shared.wasInDetachZone = true }
        }
        .onDrag { makeDragProvider(for: document) }
        .onDrop(of: [TabDragState.documentDragType],
                delegate: DocumentDropDelegate(
                    targetDocument: document,
                    store: store,
                    onInsertionIndexChange: { idx in
                        withAnimation(.spring(duration: 0.15)) { dropInsertionIndex = idx }
                    }
                ))
    }

    private var insertionIndicator: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 2, height: 22)
            .transition(.opacity.combined(with: .scale(scale: 0.7)))
    }

    // MARK: - Drag provider

    private func makeDragProvider(for document: Document) -> NSItemProvider {
        TabDragState.shared.begin(documentID: document.id, from: store)

        var upMonitor:   Any?
        var moveMonitor: Any?

        // IMPORTANT: Use addGlobalMonitorForEvents, NOT addLocalMonitorForEvents.
        // Local monitors are NOT delivered during a system drag session (.onDrag hands
        // mouse control to the OS). Global monitors fire regardless of drag state,
        // so dragTranslation accumulates correctly and the mouseUp is always caught.
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
            // 150 ms delay: lets performDrop (if any drop target accepted) call clear()
            // first, so the guard below fails for accepted drops and only passes for
            // drags that ended in empty space (= detach).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard TabDragState.shared.draggingDocumentID == document.id else { return }
                let shouldDetach = TabDragState.shared.wasInDetachZone
                TabDragState.shared.reset()
                if shouldDetach { store.detachToNewWindow(document) }
            }
        }

        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: TabDragState.documentDragType.identifier,
            visibility: .all
        ) { completion in
            let data = document.id.uuidString.data(using: .utf8) ?? Data()
            completion(data, nil)
            return nil
        }
        return provider
    }
}

// MARK: - Trailing drop delegate

private struct TrailingDropDelegate: DropDelegate {
    let store: DocumentStore
    var onInsertionIndexChange: ((Int?) -> Void)?

    func validateDrop(info: DropInfo) -> Bool { TabDragState.shared.draggingDocumentID != nil }
    func dropEntered(info: DropInfo) { onInsertionIndexChange?(store.documents.count) }
    func dropExited(info: DropInfo)  { onInsertionIndexChange?(nil) }

    func performDrop(info: DropInfo) -> Bool {
        onInsertionIndexChange?(nil)
        guard let draggingID = TabDragState.shared.draggingDocumentID else { return false }
        let sourceStore = TabDragState.shared.sourceStore
        TabDragState.shared.clear()
        if let src = sourceStore, src !== store,
           let doc = src.documents.first(where: { $0.id == draggingID }) {
            src.removeDocument(id: draggingID)
            store.insertDocument(doc, at: store.documents.count)
        } else if let fromIdx = store.documents.firstIndex(where: { $0.id == draggingID }) {
            withAnimation(.spring(duration: 0.2)) {
                store.moveTab(fromOffsets: IndexSet(integer: fromIdx),
                              toOffset: store.documents.count)
            }
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

/// Standalone horizontal tab bar (legacy / fallback).
struct HorizontalTabBarView: View {
    var body: some View {
        TabPillRowView()
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            .frame(height: ToolbarMetrics.compactPillRowHeight + 2)
    }
}
