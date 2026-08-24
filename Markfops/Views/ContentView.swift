import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(DocumentStore.self) private var store
    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @AppStorage("editorFontFamily") private var fontFamily: String = "SF Mono"

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var scrollToHeading: HeadingNode? = nil
    @State private var isSidebarTransitioning = false
    @State private var isToolbarContentVisible = true
    @State private var sidebarTransitionGeneration = 0

    private static let sidebarTransitionDuration: TimeInterval = 0.22

    private var editorConfig: EditorConfiguration {
        var config = EditorConfiguration.default
        config.fontSize = fontSize
        config.fontFamily = fontFamily
        return config
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(onTOCTap: handleTOCTap, columnVisibility: $columnVisibility)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            Group {
                if let document = store.activeDocument {
                    @Bindable var doc = document
                    EditorContainerView(
                        document: document,
                        configuration: editorConfig,
                        scrollToHeading: scrollToHeading
                    )
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            CompactToolbarPrincipalItem(
                                isCompact: columnVisibility == .detailOnly,
                                isTransitioning: isSidebarTransitioning,
                                isVisible: isToolbarContentVisible
                            )
                        }
                        ModeToggleToolbarItem(
                            mode: $doc.mode,
                            isVisible: isToolbarContentVisible
                        )
                    }
                } else {
                    WelcomeView()
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                CompactToolbarPrincipalItem(
                                    isCompact: columnVisibility == .detailOnly,
                                    isTransitioning: isSidebarTransitioning,
                                    isVisible: isToolbarContentVisible
                                )
                            }
                        }
                }
            }
            .modifier(DetailToolbarDefaultTitleRemoval(isCompact: columnVisibility == .detailOnly))
        }
        .focusedValue(\.sidebarVisibility, $columnVisibility)
        // The native title owns the draggable file proxy while the sidebar is visible.
        .navigationTitle(
            columnVisibility == .detailOnly || !isToolbarContentVisible
                ? ""
                : (store.activeDocument?.displayTitle ?? "Markfops")
        )
        // Hidden Cmd+1-9 / Cmd+0 shortcuts for tab selection — not in Commands so they don't create menu items
        .background {
            VStack {
                ForEach(1..<10, id: \.self) { i in
                    Button("") { store.selectTab(at: i - 1) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i))), modifiers: .command)
                }
                Button("") { store.activeID = store.documents.last?.id }
                    .keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleWindowDrop(providers: providers)
        }
        .onChange(of: store.activeDocument?.isDirty) { _, isDirty in
            documentWindow?.isDocumentEdited = isDirty ?? false
        }
        .onChange(of: store.activeDocument?.fileURL) { _, _ in
            refreshProxyIcon()
        }
        .onChange(of: store.activeDocument?.headings) { _, _ in
            refreshProxyIcon()
        }
        .onChange(of: store.activeID) { _, _ in
            let doc = store.activeDocument
            documentWindow?.isDocumentEdited = doc?.isDirty ?? false
            refreshProxyIcon()
        }
        .onChange(of: columnVisibility) { _, _ in
            beginSidebarTransition()
        }
    }

    /// Keeps the window proxy icon in sync with the active document.
    /// For saved files, representedURL drives the icon automatically.
    /// For unsaved files with no H1 (= no colored-badge favicon), we force-show
    /// a generic markdown icon so the proxy icon area is never empty.
    private func refreshProxyIcon() {
        guard let window = documentWindow else { return }
        let doc = store.activeDocument
        window.representedURL = doc?.fileURL

        // If the document is unsaved and has no H1, show a placeholder icon
        guard doc?.fileURL == nil,
              let btn = window.standardWindowButton(.documentIconButton) else { return }
        let hasH1 = doc?.headings.contains(where: { $0.level == 1 }) ?? false
        if !hasH1 {
            let icon = NSWorkspace.shared.icon(for: UTType("net.daringfireball.markdown") ?? .plainText)
            btn.image = icon
            btn.isHidden = false
        }
    }

    private var documentWindow: NSWindow? {
        store.managedWindow
    }

    private func beginSidebarTransition() {
        sidebarTransitionGeneration &+= 1
        let generation = sidebarTransitionGeneration

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isToolbarContentVisible = false
            isSidebarTransitioning = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sidebarTransitionDuration) {
            guard generation == sidebarTransitionGeneration else { return }
            withTransaction(transaction) {
                isSidebarTransitioning = false
            }
            DispatchQueue.main.async {
                guard generation == sidebarTransitionGeneration else { return }
                withAnimation(.easeIn(duration: 0.10)) {
                    isToolbarContentVisible = true
                }
            }
        }
    }

    private func handleTOCTap(_ heading: HeadingNode) {
        store.activeDocument?.focusHeading(heading)
        scrollToHeading = heading
        // Reset after a tick so future taps to the same heading still trigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollToHeading = nil
        }
    }

    private func handleWindowDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "md"
                        || url.pathExtension.lowercased() == "markdown"
                        || url.pathExtension.lowercased() == "txt" else { return }
                DispatchQueue.main.async {
                    store.coordinator?.open(url: url, preferredWindowID: store.windowID)
                }
            }
        }
        return true
    }
}

/// Persistent compact tab host.
///
/// Its toolbar item and tab graph remain mounted at zero width behind the native window title while
/// the sidebar is visible. Compact mode expands the same host, avoiding the expensive reconstruction
/// without replacing AppKit's draggable document title and proxy icon.
private struct CompactToolbarPrincipalItem: View {
    let isCompact: Bool
    let isTransitioning: Bool
    let isVisible: Bool
    @Environment(DocumentStore.self) private var store

    private static let reservedChromeWidth: CGFloat = 244
    private static let minimumIdealWidth: CGFloat = 180

    /// Read synchronously when SwiftUI negotiates the toolbar item. Sidebar transitions leave the
    /// window width unchanged, so the value stays fixed for the entire split-view animation.
    private var idealWidth: CGFloat {
        let windowWidth = store.managedWindow?.contentView?.bounds.width ?? 720
        return max(Self.minimumIdealWidth, windowWidth - Self.reservedChromeWidth)
    }

    private var occupiesToolbarSpace: Bool {
        isCompact && !isTransitioning
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            TabPillRowView(toolbarSlotWidth: w)
                .frame(width: w, alignment: .center)
                .clipped()
        }
        .opacity(occupiesToolbarSpace && isVisible ? 1 : 0)
        .allowsHitTesting(occupiesToolbarSpace && isVisible)
        .accessibilityHidden(!occupiesToolbarSpace || !isVisible)
        .frame(
            minWidth: occupiesToolbarSpace ? 120 : 0,
            idealWidth: occupiesToolbarSpace ? idealWidth : 0,
            maxWidth: occupiesToolbarSpace ? .infinity : 0
        )
        .frame(height: ToolbarMetrics.compactPillRowHeight)
        .layoutPriority(-1)
    }
}

/// Removes the native title only while compact tabs serve as the window label.
/// `ToolbarDefaultItemKind.title` is macOS 15+; older systems keep prior toolbar behavior.
private struct DetailToolbarDefaultTitleRemoval: ViewModifier {
    let isCompact: Bool

    func body(content: Content) -> some View {
        if isCompact {
            if #available(macOS 15.0, *) {
                content.toolbar(removing: .title)
            } else {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Welcome screen

private struct WelcomeView: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Markfops")
                .font(.largeTitle.bold())

            HStack(spacing: 12) {
                Button("New Document") { store.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                    .buttonStyle(.borderedProminent)

                Button("Open…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        store.coordinator?.open(
                            urls: panel.urls,
                            preferredWindowID: store.windowID
                        )
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}
