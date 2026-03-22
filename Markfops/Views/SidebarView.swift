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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.documents) { document in
                        TabItemView(
                            document: document,
                            isActive: store.activeID == document.id,
                            onSelect: { store.activeID = document.id },
                            onClose: { store.close(id: document.id) },
                            onTOCTap: onTOCTap
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
    }
}
