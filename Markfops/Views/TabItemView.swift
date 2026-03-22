import SwiftUI
import AppKit

/// Unified tab component used in both the sidebar (.sidebar) and the compact toolbar bar (.compact).
struct DocumentTabView: View {
    @Bindable var document: Document
    let isActive: Bool
    var style: Style = .sidebar
    let onSelect: () -> Void
    let onClose: () -> Void
    var onTOCTap: ((HeadingNode) -> Void)? = nil

    enum Style { case sidebar, compact }

    // MARK: - Size tokens
    private var faviconSize:      CGFloat { style == .compact ? 18 : 22 }
    private var faviconFontSize:  CGFloat { style == .compact ? 10 : 12 }
    private var titleFontSize:    CGFloat { style == .compact ? 12 : 13 }
    private var hSpacing:         CGFloat { style == .compact ?  5 :  8 }
    private var dotSize:          CGFloat { style == .compact ?  5 :  6 }
    private var xmarkSize:        CGFloat { style == .compact ?  8 :  9 }
    private var closeFrame:       CGFloat { style == .compact ? 14 : 16 }
    private var cornerRadius:     CGFloat { style == .compact ?  7 :  6 }

    // MARK: - State
    @State private var isHovered       = false
    @State private var isFaviconHovered = false   // sidebar only
    @State private var highlightedID: String? = nil
    @State private var isTOCVisible    = false    // sidebar only

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: hSpacing) {
                faviconSlot

                Text(document.sidebarDisplayTitle)
                    .font(.system(size: titleFontSize))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isActive ? .primary : .secondary)
                    .frame(maxWidth: style == .compact ? 120 : .infinity, alignment: .leading)
                    .mask(trailingFadeMask)
                    .animation(.easeOut(duration: 0.18), value: isHovered)
                    .animation(.easeOut(duration: 0.18), value: document.isDirty)
                    .overlay(alignment: .trailing) { closeSlot }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(pill)
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .onHover { isHovered = $0 }

            // TOC — sidebar only
            if style == .sidebar, isTOCVisible, !document.headings.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleHeadings) { heading in
                        TOCItemView(
                            heading: heading,
                            isHighlighted: highlightedID == heading.id,
                            isCollapsible: headingHasChildren(heading),
                            isCollapsed: document.collapsedHeadingIDs.contains(heading.id),
                            onTap: {
                                highlightedID = heading.id
                                onTOCTap?(heading)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    highlightedID = nil
                                }
                            },
                            onToggleCollapse: { toggleCollapse(heading) }
                        )
                    }
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            isTOCVisible = isActive && document.isTOCExpanded
        }
        .onChange(of: isActive) { _, active in
            withAnimation(.spring(duration: 0.22)) {
                isTOCVisible = active && document.isTOCExpanded
            }
        }
    }

    // MARK: - Sub-views

    /// Favicon badge; in sidebar it also doubles as the TOC toggle on hover.
    @ViewBuilder private var faviconSlot: some View {
        if style == .sidebar {
            ZStack {
                FaviconBadge(
                    letter: document.faviconLetter,
                    size: faviconSize,
                    fontSize: faviconFontSize,
                    fileURL: document.fileURL,
                    hasH1: document.headings.contains(where: { $0.level == 1 })
                )
                .opacity(isFaviconHovered ? 0 : 1)
                .onDrag {
                    guard let url = document.fileURL else { return NSItemProvider() }
                    return NSItemProvider(object: url as NSURL)
                }
                .contextMenu { faviconContextMenu }

                Button(action: {
                    withAnimation(.spring(duration: 0.22)) {
                        isTOCVisible.toggle()
                        document.isTOCExpanded = isTOCVisible
                    }
                }) {
                    Image(systemName: isTOCVisible ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: faviconSize, height: faviconSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(document.headings.isEmpty ? 0.2 : (isFaviconHovered ? 1 : 0))
                .disabled(document.headings.isEmpty)
            }
            .frame(width: faviconSize, height: faviconSize)
            .onHover { isFaviconHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isFaviconHovered)
        } else {
            FaviconBadge(
                letter: document.faviconLetter,
                size: faviconSize,
                fontSize: faviconFontSize,
                fileURL: document.fileURL,
                hasH1: document.headings.contains(where: { $0.level == 1 })
            )
        }
    }

    @ViewBuilder private var faviconContextMenu: some View {
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

    /// Trailing gradient that fades the text edge as the close button appears.
    private var trailingFadeMask: LinearGradient {
        let fade = isHovered || document.isDirty
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: fade ? 0.60 : 1.0),
                .init(color: .clear,  location: fade ? 0.90 : 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Dirty dot + close button, overlaid on the trailing edge of the text.
    private var closeSlot: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: dotSize, height: dotSize)
                .opacity(document.isDirty && !isHovered ? 1 : 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: xmarkSize, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: closeFrame, height: closeFrame)
            .opacity(isHovered ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.18), value: isHovered)
    }

    /// Background + optional pill border (compact only shows hover fill and active stroke).
    private var pill: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                isActive
                    ? Color(NSColor.controlAccentColor).opacity(0.15)
                    : (style == .compact && isHovered
                        ? Color(NSColor.quaternaryLabelColor)
                        : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        style == .compact && isActive
                            ? Color.accentColor.opacity(0.3)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
    }

    // MARK: - TOC helpers

    private var visibleHeadings: [HeadingNode] {
        var result: [HeadingNode] = []
        var collapsedAtLevel: Int? = nil
        for heading in document.headings {
            guard heading.level > 1 else { continue }
            if let colLevel = collapsedAtLevel {
                if heading.level <= colLevel { collapsedAtLevel = nil } else { continue }
            }
            result.append(heading)
            if document.collapsedHeadingIDs.contains(heading.id) {
                collapsedAtLevel = heading.level
            }
        }
        return result
    }

    private func headingHasChildren(_ heading: HeadingNode) -> Bool {
        let nonH1 = document.headings.filter { $0.level > 1 }
        guard let idx = nonH1.firstIndex(where: { $0.id == heading.id }),
              idx + 1 < nonH1.count else { return false }
        return nonH1[idx + 1].level > heading.level
    }

    private func toggleCollapse(_ heading: HeadingNode) {
        if document.collapsedHeadingIDs.contains(heading.id) {
            document.collapsedHeadingIDs.remove(heading.id)
        } else {
            document.collapsedHeadingIDs.insert(heading.id)
        }
    }

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
