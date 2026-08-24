import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(DocumentStore.self) private var store
    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @AppStorage("editorFontFamily") private var fontFamily: String = "SF Mono"

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var scrollToHeading: HeadingNode? = nil

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
                        if #available(macOS 15.0, *) {
                            ToolbarItem(placement: .principal) {
                                DetailToolbarPrincipalItem(
                                    isCompact: columnVisibility == .detailOnly,
                                    title: document.displayTitle
                                )
                            }
                        } else if columnVisibility == .detailOnly {
                            ToolbarItem(placement: .principal) {
                                DetailToolbarPrincipalItem(isCompact: true, title: document.displayTitle)
                            }
                        }
                        ModeToggleToolbarItem(mode: $doc.mode)
                    }
                } else {
                    WelcomeView()
                        .toolbar {
                            if #available(macOS 15.0, *) {
                                ToolbarItem(placement: .principal) {
                                    DetailToolbarPrincipalItem(
                                        isCompact: columnVisibility == .detailOnly,
                                        title: "Markfops"
                                    )
                                }
                            } else if columnVisibility == .detailOnly {
                                ToolbarItem(placement: .principal) {
                                    DetailToolbarPrincipalItem(isCompact: true, title: "Markfops")
                                }
                            }
                        }
                }
            }
            // A single custom principal item owns both the title and compact tabs. Keeping the
            // toolbar topology stable avoids an expensive AppKit retile on every sidebar toggle.
            .modifier(DetailToolbarDefaultTitleRemoval())
        }
        .focusedValue(\.sidebarVisibility, $columnVisibility)
        // Keep the semantic window title even though the system toolbar title item is replaced.
        .navigationTitle(navigationTitle)
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

    private var navigationTitle: String {
        let title = store.activeDocument?.displayTitle ?? "Markfops"
        if #available(macOS 15.0, *) {
            return title
        }
        return columnVisibility == .detailOnly ? "" : title
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

/// Stable principal toolbar host shared by sidebar and compact layouts.
///
/// The tab row remains mounted while the sidebar is visible. Destroying and recreating it for every
/// toggle makes SwiftUI rebuild the tab accessibility/layout graph and forces `NSToolbarView` to
/// retile during the 220 ms split-view animation. Opacity and hit-testing changes preserve the same
/// toolbar items and hosting view across both states.
private struct DetailToolbarPrincipalItem: View {
    let isCompact: Bool
    let title: String

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            ZStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: w)
                    .opacity(isCompact ? 0 : 1)
                    .accessibilityHidden(isCompact)

                TabPillRowView(toolbarSlotWidth: w)
                    .frame(width: w, alignment: .center)
                    .clipped()
                    .opacity(isCompact ? 1 : 0)
                    .allowsHitTesting(isCompact)
                    .accessibilityHidden(!isCompact)
            }
        }
        // The sidebar leaves a much narrower detail-title region. Bounding the title host keeps
        // the mode control out of NSToolbar's overflow menu, while compact mode still receives the
        // flexible space needed by the scrollable tab strip.
        .frame(
            minWidth: isCompact ? 120 : 80,
            idealWidth: isCompact ? 300 : 160,
            maxWidth: isCompact ? .infinity : 240
        )
        .frame(height: ToolbarMetrics.compactPillRowHeight)
        .layoutPriority(-1)
    }
}

/// Removes the system title toolbar item because the stable principal host renders the title.
/// `ToolbarDefaultItemKind.title` is macOS 15+; older systems keep prior toolbar behavior.
private struct DetailToolbarDefaultTitleRemoval: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
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
