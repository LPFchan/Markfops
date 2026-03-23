import SwiftUI
import AppKit

// MARK: - Shared context menu (identical between sidebar and compact)

struct DocumentContextMenu: View {
    @Environment(DocumentStore.self) private var store
    let document: Document
    let onClose: () -> Void

    var body: some View {
        Group {
            if document.isDirty {
                Button("Save") { try? store.save(document) }
            }
            Button("Save As\u{2026}") { try? store.saveAs(document) }

            Divider()

            Button("Rename\u{2026}") { store.rename(document) }
            if document.fileURL != nil {
                Button("Move To\u{2026}") { store.moveTo(document) }
            }
            Button("Duplicate") { store.duplicate(document) }
            if let url = document.fileURL {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }

            Divider()

            Button("Export as PDF\u{2026}") { store.exportAsPDF(document) }
            if document.isDirty, document.fileURL != nil {
                Divider()
                Button("Revert to Saved") { store.revertToSaved(document) }
            }

            Divider()

            Button("Move to New Window") { store.detachToNewWindow(document) }

            Divider()

            Button("Close Tab") { onClose() }
        }
    }
}

// MARK: - Drop delegate for tab reordering

struct DocumentDropDelegate: DropDelegate {
    let targetDocument: Document
    let store: DocumentStore

    func validateDrop(info: DropInfo) -> Bool {
        guard let id = store.draggingDocumentID else { return false }
        return id != targetDocument.id
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = store.draggingDocumentID,
              dragging != targetDocument.id,
              let fromIdx = store.documents.firstIndex(where: { $0.id == dragging }),
              let toIdx   = store.documents.firstIndex(where: { $0.id == targetDocument.id })
        else { return }
        withAnimation(.spring(duration: 0.2)) {
            store.moveTab(fromOffsets: IndexSet(integer: fromIdx),
                          toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        // A tab accepted the drop — cancel the pending detach
        store.draggingDocumentID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Sidebar row (pinned section header in SidebarView)

struct SidebarTabRowView: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var document: Document
    let isActive: Bool
    @Binding var isTOCVisible: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered        = false
    @State private var isFaviconHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Favicon slot: shows TOC chevron on hover
            ZStack {
                FaviconBadge(
                    letter: document.faviconLetter,
                    size: 22, fontSize: 12,
                    fileURL: document.fileURL,
                    hasH1: document.headings.contains(where: { $0.level == 1 })
                )
                .opacity(isFaviconHovered ? 0 : 1)

                Button(action: {
                    withAnimation(.spring(duration: 0.22)) {
                        isTOCVisible.toggle()
                        document.isTOCExpanded = isTOCVisible
                    }
                }) {
                    Image(systemName: isTOCVisible ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(document.headings.isEmpty ? 0.2 : (isFaviconHovered ? 1 : 0))
                .disabled(document.headings.isEmpty)
            }
            .frame(width: 22, height: 22)
            .onHover { isFaviconHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isFaviconHovered)

            Text(document.sidebarDisplayTitle)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(trailingFadeMask)
                .animation(.easeOut(duration: 0.18), value: isHovered)
                .animation(.easeOut(duration: 0.18), value: document.isDirty)
                .overlay(alignment: .trailing) { closeSlot }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(NSColor.controlAccentColor).opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Single tap: rename when already active (Finder-style), select otherwise
            if isActive { store.rename(document) } else { onSelect() }
        }
        .onHover { isHovered = $0 }
        .contextMenu { DocumentContextMenu(document: document, onClose: onClose) }
        // Solid background so scrolling TOC content doesn't bleed through the pinned header
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Styling

    private var trailingFadeMask: LinearGradient {
        let fade = isHovered || document.isDirty
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: fade ? 0.60 : 1.0),
                .init(color: .clear,  location: fade ? 0.90 : 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var closeSlot: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .opacity(document.isDirty && !isHovered ? 1 : 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)   // expanded hit target (icon stays 9pt)
            .contentShape(Rectangle())
            .opacity(isHovered ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.18), value: isHovered)
    }
}

// MARK: - Compact tab pill (toolbar tab bar)

struct DocumentTabView: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var document: Document
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            FaviconBadge(
                letter: document.faviconLetter,
                size: 18, fontSize: 10,
                fileURL: document.fileURL,
                hasH1: document.headings.contains(where: { $0.level == 1 })
            )

            Text(document.sidebarDisplayTitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
                .mask(trailingFadeMask)
                .animation(.easeOut(duration: 0.18), value: isHovered)
                .animation(.easeOut(duration: 0.18), value: document.isDirty)
                .overlay(alignment: .trailing) { closeSlot }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive
                    ? Color(NSColor.controlAccentColor).opacity(0.15)
                    : (isHovered ? Color(NSColor.quaternaryLabelColor) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isActive { store.rename(document) } else { onSelect() }
        }
        .onHover { isHovered = $0 }
        .contextMenu { DocumentContextMenu(document: document, onClose: onClose) }
    }

    private var trailingFadeMask: LinearGradient {
        let fade = isHovered || document.isDirty
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: fade ? 0.60 : 1.0),
                .init(color: .clear,  location: fade ? 0.90 : 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var closeSlot: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .opacity(document.isDirty && !isHovered ? 1 : 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)   // expanded hit target (was 14)
            .contentShape(Rectangle())
            .opacity(isHovered ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.18), value: isHovered)
    }
}
