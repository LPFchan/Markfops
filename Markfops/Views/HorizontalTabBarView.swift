import SwiftUI

/// Scrollable tab pill row — used as the toolbar's principal item in compact mode.
struct TabPillRowView: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.documents) { document in
                        DocumentTabView(
                            document: document,
                            isActive: store.activeID == document.id,
                            onSelect: { store.activeID = document.id },
                            onClose: { store.close(id: document.id) }
                        )
                        .id(document.id)
                        // ── Drag to reorder / drag to new window ──────────────────────
                        .onDrag {
                            store.draggingDocumentID = document.id

                            var monitor: Any?
                            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                                if let m = monitor { NSEvent.removeMonitor(m) }
                                monitor = nil
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

                    // New tab button
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
                    .help("New Tab  ⌘T")

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .onChange(of: store.activeID) { _, newID in
                if let id = newID {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}

/// Standalone horizontal tab bar shown below the toolbar (legacy / fallback use).
struct HorizontalTabBarView: View {
    var body: some View {
        TabPillRowView()
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            .frame(height: 42)
    }
}
