import SwiftUI

struct HorizontalTabBarView: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.documents) { document in
                        TabPillView(
                            document: document,
                            isActive: store.activeID == document.id,
                            onSelect: { store.activeID = document.id },
                            onClose: { store.close(id: document.id) }
                        )
                        .id(document.id)
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
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
        .frame(height: 42)
    }
}
