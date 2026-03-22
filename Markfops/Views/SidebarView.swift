import SwiftUI

struct SidebarView: View {
    @Environment(DocumentStore.self) private var store
    var onTOCTap: (HeadingNode) -> Void

    var body: some View {
        @Bindable var bindableStore = store

        VStack(spacing: 0) {
            // Sidebar header
            HStack {
                Text("Documents")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button(action: { store.newDocument() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("New Document")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.documents) { document in
                            DocumentTabView(
                                document: document,
                                isActive: store.activeID == document.id,
                                style: .sidebar,
                                onSelect: { store.activeID = document.id },
                                onClose: { store.close(id: document.id) },
                                onTOCTap: onTOCTap
                            )
                            .id(document.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .onChange(of: store.activeID) { _, newID in
                    guard let id = newID else { return }
                    // Delay slightly so the TOC spring animation finishes before scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
    }
}
