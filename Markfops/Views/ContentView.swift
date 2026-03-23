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
            if let document = store.activeDocument {
                @Bindable var doc = document
                EditorContainerView(
                    document: document,
                    configuration: editorConfig,
                    scrollToHeading: scrollToHeading
                )
                .toolbar {
                    if columnVisibility == .detailOnly {
                        // Compact mode: pill row + toggle share the principal slot.
                        // Principal never overflows, so the toggle is always visible.
                        ToolbarItem(placement: .principal) {
                            HStack(spacing: 10) {
                                TabPillRowView()
                                // Thin divider visually separates pills from toggle
                                Divider()
                                    .frame(height: 18)
                                Picker("Mode", selection: $doc.mode) {
                                    Label("Edit",    systemImage: "pencil").tag(EditMode.edit)
                                    Label("Preview", systemImage: "eye"   ).tag(EditMode.preview)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                                .fixedSize()
                                .help("Toggle Edit / Preview  ⌘⇧P")
                            }
                        }
                    } else {
                        // Sidebar mode: toggle sits in the trailing toolbar area.
                        ModeToggleToolbarItem(mode: $doc.mode)
                    }
                }
            } else {
                WelcomeView()
                    .toolbar {
                        if columnVisibility == .detailOnly {
                            ToolbarItem(placement: .principal) {
                                TabPillRowView()
                                    .frame(maxWidth: 600)
                            }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            EmptyView()
                        }
                    }
            }
        }
        .focusedValue(\.sidebarVisibility, $columnVisibility)
        // In compact mode hide the window title — tabs serve as the label
        .navigationTitle(columnVisibility == .detailOnly ? "" : (store.activeDocument?.displayTitle ?? "Markfops"))
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
            NSApp.mainWindow?.isDocumentEdited = isDirty ?? false
        }
        .onChange(of: store.activeDocument?.fileURL) { _, _ in
            refreshProxyIcon()
        }
        .onChange(of: store.activeDocument?.headings) { _, _ in
            refreshProxyIcon()
        }
        .onChange(of: store.activeID) { _, _ in
            let doc = store.activeDocument
            NSApp.mainWindow?.isDocumentEdited = doc?.isDirty ?? false
            refreshProxyIcon()
        }
    }

    /// Keeps the window proxy icon in sync with the active document.
    /// For saved files, representedURL drives the icon automatically.
    /// For unsaved files with no H1 (= no colored-badge favicon), we force-show
    /// a generic markdown icon so the proxy icon area is never empty.
    private func refreshProxyIcon() {
        guard let window = NSApp.mainWindow else { return }
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

    private func handleTOCTap(_ heading: HeadingNode) {
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
                    store.open(url: url)
                }
            }
        }
        return true
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

            Text("Lightweight Markdown editor for macOS")
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("New Document") { store.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                    .buttonStyle(.borderedProminent)

                Button("Open…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        for url in panel.urls { store.open(url: url) }
                    }
                }
                .buttonStyle(.bordered)
            }

            Text("Drop a .md file anywhere to open it")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}
