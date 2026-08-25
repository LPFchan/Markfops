import SwiftUI
import AppKit

// MARK: - NSView background that prevents the window from moving when a tab pill is pressed.
// Critical in compact/toolbar mode: without this, the toolbar intercepts mouseDown events
// for window dragging before SwiftUI's .onDrag gets them.

private struct TabBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Backing() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private class Backing: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// NSToolbar claims secondary clicks before a SwiftUI context-menu gesture can see them. Keep one
/// lightweight monitor for the currently hovered tab so compact mode can replace only that click;
/// every other toolbar click still uses normal AppKit behavior.
@MainActor
final class CompactTabContextMenuController: NSObject {
    struct Configuration {
        let documentID: UUID
        let canCloseOthers: Bool
        let canCloseLeft: Bool
        let canCloseRight: Bool
        let onClose: () -> Void
        let onCloseOthers: () -> Void
        let onCloseLeft: () -> Void
        let onCloseRight: () -> Void
        let onMoveToNewWindow: () -> Void
    }

    static let shared = CompactTabContextMenuController()

    static func start() {
        _ = shared
    }

    private var hovered: Configuration?
    private var presented: Configuration?
    private var eventMonitor: Any?

    private override init() {
        super.init()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let hovered = self.hovered else { return event }
            let menu = self.makeMenu(for: hovered)
            let anchor = event.window?.contentView ?? NSApp.keyWindow?.contentView
            guard let anchor else { return event }
            self.presented = hovered
            NSMenu.popUpContextMenu(menu, with: event, for: anchor)
            self.presented = nil
            return nil
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    func setHovered(_ configuration: Configuration) {
        hovered = configuration
    }

    func clearHovered(documentID: UUID) {
        guard hovered?.documentID == documentID else { return }
        hovered = nil
    }

    private func makeMenu(for configuration: Configuration) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("Close", action: #selector(closeTab)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Close Other Tabs", action: #selector(closeOtherTabs), enabled: configuration.canCloseOthers))
        menu.addItem(menuItem("Close Tabs to the Left", action: #selector(closeTabsToLeft), enabled: configuration.canCloseLeft))
        menu.addItem(menuItem("Close Tabs to the Right", action: #selector(closeTabsToRight), enabled: configuration.canCloseRight))
        menu.addItem(.separator())
        menu.addItem(menuItem("Move Tab to New Window", action: #selector(moveToNewWindow)))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString(title, comment: "Compact tab context menu"),
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func closeTab() { presented?.onClose() }
    @objc private func closeOtherTabs() { presented?.onCloseOthers() }
    @objc private func closeTabsToLeft() { presented?.onCloseLeft() }
    @objc private func closeTabsToRight() { presented?.onCloseRight() }
    @objc private func moveToNewWindow() { presented?.onMoveToNewWindow() }
}

// MARK: - Sidebar document context menu

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

            Button("Move to New Window") {
                store.detachToNewWindow(document)
            }

            Divider()

            Button("Export as PDF\u{2026}") { store.exportAsPDF(document) }
            if document.isDirty, document.fileURL != nil {
                Divider()
                Button("Revert to Saved") { store.revertToSaved(document) }
            }

            Divider()

            Button("Close Tab") { onClose() }
        }
    }
}

// MARK: - Drop delegate for tab reordering

struct DocumentDropDelegate: DropDelegate {
    let targetDocument: Document
    let store: DocumentStore
    /// Called with the target index when the drag enters this pill, nil when it exits or drops.
    var onInsertionIndexChange: ((Int?) -> Void)?

    func validateDrop(info: DropInfo) -> Bool {
        guard let id = TabDragState.shared.draggingDocumentID else { return false }
        return id != targetDocument.id
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID = TabDragState.shared.draggingDocumentID,
              draggingID != targetDocument.id else { return }

        if let toIdx = store.documents.firstIndex(where: { $0.id == targetDocument.id }) {
            onInsertionIndexChange?(toIdx)
        }

        guard let fromIdx = store.documents.firstIndex(where: { $0.id == draggingID }),
              let toIdx   = store.documents.firstIndex(where: { $0.id == targetDocument.id })
        else { return }

        withAnimation(.spring(duration: 0.2)) {
            store.moveTab(fromOffsets: IndexSet(integer: fromIdx),
                          toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        }
    }

    func dropExited(info: DropInfo) {
        onInsertionIndexChange?(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        onInsertionIndexChange?(nil)
        guard let draggingID = TabDragState.shared.draggingDocumentID else { return false }

        let sourceStore = TabDragState.shared.sourceStore
        let sourceID = sourceStore?.windowID
        let targetIndex = store.documents.firstIndex(where: { $0.id == targetDocument.id }) ?? store.documents.count
        TabDragState.shared.clear()
        if let sourceStore, sourceStore !== store, let sourceID {
            store.coordinator?.move(documentID: draggingID, from: sourceID, to: store.windowID, at: targetIndex)
            return true
        }
        guard store.documents.contains(where: { $0.id == draggingID }) else { return false }
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
    var isInDetachZone: Bool = false
    @State private var isHovered        = false
    @State private var isFaviconHovered = false
    @State private var isCloseHovered   = false
    @State private var isRenaming       = false
    @State private var renameText       = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var renameTask: Task<Void, Never>? = nil

    var body: some View {
        HStack(spacing: 8) {

            // Favicon slot: shows TOC chevron on hover
            ZStack {
                FaviconBadge(
                    letter: document.faviconLetter,
                    size: 22, fontSize: 12,
                    fileURL: document.fileURL,
                    hasH1: document.hasH1
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
            .animation(.spring(duration: 0.15), value: isFaviconHovered)

            // Title / rename field
            Group {
                if isRenaming {
                    TextField("", text: $renameText)
                        .font(.system(size: 13))
                        .focused($renameFieldFocused)
                        .onSubmit { commitRename() }
                        .onKeyPress(.escape) { isRenaming = false; return .handled }
                        .onAppear { renameFieldFocused = true }
                } else if isInDetachZone {
                    Label("New Window", systemImage: "macwindow")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(document.sidebarDisplayTitle)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(isActive ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mask(trailingFadeMask)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(duration: 0.18), value: isRenaming)

            // Close button — fixed width, always at trailing edge
            if !isRenaming {
                closeSlot
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: isInDetachZone ? 4 : 6)
                .fill(isActive
                    ? Color(NSColor.controlAccentColor).opacity(0.15)
                    : Color.clear)
        )
        .overlay {
            if isInDetachZone {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        // Rename: only schedule when this doc is already active (not on switch-to).
        .onTapGesture {
            if isActive {
                scheduleRename()
            } else {
                renameTask?.cancel()
                onSelect()
            }
        }
        // Cancel rename when mouse leaves or this row loses active state.
        .onHover { hovered in
            isHovered = hovered
            if !hovered { renameTask?.cancel() }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                renameTask?.cancel()
                isRenaming = false
            }
        }
        .contextMenu { DocumentContextMenu(document: document, onClose: onClose) }
        .background(Color(NSColor.windowBackgroundColor))
        .background(TabBackground())
    }

    // MARK: - Rename

    private func scheduleRename() {
        renameTask?.cancel()
        renameTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch { return }
            guard isHovered, !isRenaming,
                  TabDragState.shared.draggingDocumentID == nil else { return }
            if let url = document.fileURL {
                renameText = url.deletingPathExtension().lastPathComponent
                isRenaming = true
            } else {
                try? store.saveAs(document)
            }
        }
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { isRenaming = false; return }
        store.renameInline(document: document, newBaseName: name)
        isRenaming = false
    }

    // MARK: - Styling

    /// Fade the title text into where the close button starts (right edge of the text frame).
    private var trailingFadeMask: LinearGradient {
        let fade = isHovered || document.isDirty
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: fade ? 0.72 : 1.0),
                .init(color: .clear,  location: fade ? 1.00 : 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    /// Close (×) slot — fixed 20×20pt frame so the text width never jumps.
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
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.quaternaryLabelColor))
                    .opacity(isCloseHovered ? 0.8 : 0)
            )
            .onHover { isCloseHovered = $0 }
            .opacity(isHovered ? 1 : 0)
        }
        .frame(width: 20, height: 20)
        .animation(.spring(duration: 0.18), value: isHovered)
        .animation(.spring(duration: 0.12), value: isCloseHovered)
    }
}

// MARK: - Compact tab pill (toolbar tab bar)

struct DocumentTabView: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var document: Document
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    var isInDetachZone: Bool = false
    /// Dynamic width passed from TabPillRowView; nil = hug content.
    var pillWidth: CGFloat? = nil

    /// Below this width, show favicon only (no title) so tabs can shrink with the window.
    private var isIconOnly: Bool {
        guard let w = pillWidth else { return false }
        return w < TabPillSizing.iconOnlyThreshold
    }

    private var faviconSize: CGFloat {
        guard let w = pillWidth else { return 18 }
        if w < 30 { return 14 }
        if w < 42 { return 16 }
        return 18
    }

    private var faviconFontSize: CGFloat {
        max(8, min(11, faviconSize * 0.56))
    }

    private var horizontalPadding: CGFloat {
        guard let w = pillWidth else { return 10 }
        if w < 56 { return 4 }
        if w < 72 { return 6 }
        return 10
    }

    private var tabIndex: Int? {
        store.documents.firstIndex(where: { $0.id == document.id })
    }

    private var contextMenuConfiguration: CompactTabContextMenuController.Configuration {
        .init(
            documentID: document.id,
            canCloseOthers: store.documents.count > 1,
            canCloseLeft: (tabIndex ?? 0) > 0,
            canCloseRight: tabIndex.map { $0 < store.documents.count - 1 } ?? false,
            onClose: onClose,
            onCloseOthers: { store.closeTabs(relativeTo: document.id, scope: .others) },
            onCloseLeft: { store.closeTabs(relativeTo: document.id, scope: .left) },
            onCloseRight: { store.closeTabs(relativeTo: document.id, scope: .right) },
            onMoveToNewWindow: { store.detachToNewWindow(document) }
        )
    }

    @State private var isHovered      = false
    @State private var isCloseHovered = false
    @State private var isRenaming     = false
    @State private var renameText     = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var renameTask: Task<Void, Never>? = nil

    private var faviconView: some View {
        FaviconBadge(
            letter: document.faviconLetter,
            size: faviconSize,
            fontSize: faviconFontSize,
            fileURL: document.fileURL,
            hasH1: document.hasH1
        )
    }

    var body: some View {
        Group {
            if isInDetachZone {
                Label("New Window", systemImage: "macwindow")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .lineLimit(1)
            } else if isIconOnly && !isRenaming {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    faviconView
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 5) {
                    faviconView

                    // Title / rename field — fills remaining space. A fixed trailing clearance
                    // reserves room for the close button so its fade ends at the button's
                    // leading edge instead of extending to the pill's right edge.
                    Group {
                        if isRenaming {
                            TextField("", text: $renameText)
                                .font(.system(size: 12))
                                .focused($renameFieldFocused)
                                .frame(maxWidth: .infinity)
                                .onSubmit { commitRename() }
                                .onKeyPress(.escape) { isRenaming = false; return .handled }
                                .onAppear { renameFieldFocused = true }
                        } else {
                            Text(document.sidebarDisplayTitle)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, fadeClearance)
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .black, location: 0),
                                            .init(color: .black, location: 0.88),
                                            .init(color: .clear,  location: 1.00),
                                        ],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                        }
                    }
                    .animation(.spring(duration: 0.18), value: isRenaming)

                    // Close (×) button sits right after the title, inside the reserved clearance.
                    if !isRenaming { closeSlot }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 6)
        .frame(width: pillWidth)
        .background(
            RoundedRectangle(cornerRadius: isInDetachZone ? 3 : 7)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isInDetachZone ? 3 : 7)
                .stroke(
                    isInDetachZone ? Color.accentColor : (isActive ? Color.accentColor.opacity(0.3) : Color.clear),
                    lineWidth: isInDetachZone ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .background(TabBackground())
        // Rename: only schedule when already the active doc.
        .onTapGesture {
            CompactTabContextMenuController.shared.setHovered(contextMenuConfiguration)
            if isActive {
                if !isIconOnly { scheduleRename() }
            } else {
                renameTask?.cancel()
                onSelect()
            }
        }
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                CompactTabContextMenuController.shared.setHovered(contextMenuConfiguration)
            } else {
                CompactTabContextMenuController.shared.clearHovered(documentID: document.id)
            }
            if !hovered || isIconOnly { renameTask?.cancel() }
        }
        // Cancel rename when this pill becomes inactive (user clicked another tab).
        .onChange(of: isActive) { _, active in
            if !active {
                renameTask?.cancel()
                isRenaming = false
            }
        }
        .accessibilityLabel(document.sidebarDisplayTitle)
    }

    // MARK: - Rename

    private func scheduleRename() {
        guard !isIconOnly else { return }
        renameTask?.cancel()
        renameTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch { return }
            guard isHovered, !isRenaming,
                  TabDragState.shared.draggingDocumentID == nil else { return }
            if let url = document.fileURL {
                renameText = url.deletingPathExtension().lastPathComponent
                isRenaming = true
            } else {
                try? store.saveAs(document)
            }
        }
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { isRenaming = false; return }
        store.renameInline(document: document, newBaseName: name)
        isRenaming = false
    }

    // MARK: - Styling

    private var backgroundFill: Color {
        if isActive { return Color(NSColor.controlAccentColor).opacity(0.15) }
        if isHovered { return Color(NSColor.quaternaryLabelColor) }
        return Color.clear
    }

    /// Fixed trailing clearance on the title so its fade lands at the close button's
    /// leading edge, regardless of hover state. Matches closeSlot's 16pt width.
    private var fadeClearance: CGFloat { 18 }

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
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(NSColor.quaternaryLabelColor))
                    .opacity(isCloseHovered ? 0.8 : 0)
            )
            .onHover { isCloseHovered = $0 }
            .opacity(isHovered ? 1 : 0)
        }
        .frame(width: 16, height: 16)
        .animation(.spring(duration: 0.18), value: isHovered)
        .animation(.spring(duration: 0.12), value: isCloseHovered)
    }
}
