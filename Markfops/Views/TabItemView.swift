import SwiftUI
import AppKit

struct TabItemView: View {
    @Bindable var document: Document
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onTOCTap: (HeadingNode) -> Void

    @State private var isHovered = false
    @State private var highlightedID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main tab row
            HStack(spacing: 8) {
                // TOC disclosure triangle
                Button(action: { document.isTOCExpanded.toggle() }) {
                    Image(systemName: document.isTOCExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .opacity(document.headings.isEmpty ? 0.2 : 1.0)
                .disabled(document.headings.isEmpty)

                FaviconBadge(
                    letter: document.faviconLetter,
                    size: 22,
                    fontSize: 12,
                    fileURL: document.fileURL,
                    hasH1: document.headings.contains(where: { $0.level == 1 })
                )
                .onDrag {
                    guard let url = document.fileURL else { return NSItemProvider() }
                    return NSItemProvider(object: url as NSURL)
                }
                .contextMenu {
                    if let url = document.fileURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Divider()
                        ForEach(pathAncestors(of: url), id: \.path) { ancestor in
                            Button(ancestor.path == "/" ? "/" : ancestor.lastPathComponent) {
                                NSWorkspace.shared.open(ancestor)
                            }
                        }
                    }
                }

                Text(document.displayTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isActive ? .primary : .secondary)

                Spacer()

                if document.isDirty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }

                if isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .onHover { isHovered = $0 }

            // TOC expansion
            if document.isTOCExpanded && !document.headings.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(document.headings) { heading in
                        TOCItemView(
                            heading: heading,
                            isHighlighted: highlightedID == heading.id
                        ) {
                            highlightedID = heading.id
                            onTOCTap(heading)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                highlightedID = nil
                            }
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    /// Builds the ancestor chain from root to the given URL (like the proxy icon path menu).
    private func pathAncestors(of url: URL) -> [URL] {
        var ancestors: [URL] = []
        var current = url.standardizedFileURL
        for _ in 0..<40 {
            ancestors.insert(current, at: 0)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { break }
            current = parent
        }
        return ancestors
    }
}
