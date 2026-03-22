import SwiftUI

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
            SidebarView(onTOCTap: handleTOCTap)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                // Show tab bar whenever sidebar is collapsed
                if columnVisibility == .detailOnly {
                    HorizontalTabBarView()
                }

                if let document = store.activeDocument {
                    @Bindable var doc = document
                    EditorContainerView(
                        document: document,
                        configuration: editorConfig,
                        scrollToHeading: scrollToHeading
                    )
                    .toolbar {
                        ModeToggleToolbarItem(mode: $doc.mode)
                    }
                } else {
                    WelcomeView()
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                EmptyView()
                            }
                        }
                }
            }
        }
        .navigationTitle(store.activeDocument?.displayTitle ?? "Markfops")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleWindowDrop(providers: providers)
        }
        .onChange(of: store.activeDocument?.isDirty) { _, isDirty in
            NSApp.mainWindow?.isDocumentEdited = isDirty ?? false
        }
        .onChange(of: store.activeDocument?.fileURL) { _, url in
            NSApp.mainWindow?.representedURL = url
        }
        .onChange(of: store.activeID) { _, _ in
            let doc = store.activeDocument
            NSApp.mainWindow?.representedURL = doc?.fileURL
            NSApp.mainWindow?.isDocumentEdited = doc?.isDirty ?? false
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
