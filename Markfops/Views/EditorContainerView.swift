import SwiftUI

struct EditorContainerView: View {
    @Bindable var document: Document
    var configuration: EditorConfiguration
    var scrollToHeading: HeadingNode?
    var isSelected = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var htmlContent: String = ""
    @State private var bodyHTML: String = ""
    @State private var renderedDocumentID: UUID?
    @State private var renderedTextRevision: UInt64?
    @State private var renderedThemeKey: String?
    @State private var renderedContentRevision: UInt64 = 0
    @State private var isDragTargeted = false
    /// Bridges live on the document so ContentView can drive viewport-anchor capture
    /// through the same instances during sidebar/compact transitions.
    private var bridge: PreviewBridge { document.sharedPreviewBridge }
    private var editorBridge: EditorBridge { document.sharedEditorBridge }
    @State private var findController = FindController()

    private var findOverlayReservedTopInset: CGFloat {
        guard findController.isVisible else { return 0 }
        if findController.showsReplace && document.mode == .edit {
            return 122
        }
        return 74
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep one AppKit editor and one WebKit preview alive for the active document.
            // Toggling visibility avoids destroying their layout, undo, and page state.
            EditorView(
                text: $document.rawText,
                document: document,
                configuration: configuration,
                scrollToLine: scrollToHeading?.lineNumber,
                editorBridge: editorBridge,
                isActive: isSelected && document.mode == .edit
            )
            .id(document.id)
            .padding(.top, findOverlayReservedTopInset)
            .opacity(document.mode == .edit ? 1 : 0)
            .allowsHitTesting(document.mode == .edit)
            .accessibilityHidden(document.mode != .edit)
            .focusedValue(\.editorBridge, editorBridge)

            PreviewView(
                document: document,
                pageHTML: htmlContent,
                bodyHTML: bodyHTML,
                contentRevision: renderedContentRevision,
                themeKey: colorScheme == .dark ? "dark" : "light",
                bridge: bridge,
                isActive: isSelected && document.mode == .preview,
                onScrollChange: { ratio in
                    guard isSelected, document.mode == .preview else { return }
                    document.scrollRatio = ratio
                    document.syncActiveHeadingToScrollPosition()
                },
                onUserScroll: {
                    guard isSelected, document.mode == .preview else { return }
                    document.registerUserContentScroll()
                }
            )
            .padding(.top, findOverlayReservedTopInset)
            .opacity(document.mode == .preview ? 1 : 0)
            .allowsHitTesting(document.mode == .preview)
            .accessibilityHidden(document.mode != .preview)
            .focusedValue(\.previewBridge, bridge)

            if findController.isVisible {
                FindReplaceBar(controller: findController)
                    .zIndex(2)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: findController.isVisible)
        .overlay(
            isDragTargeted
                ? RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .allowsHitTesting(false)
                : nil
        )
        .modifier(SelectedDocumentFocusValues(
            isSelected: isSelected,
            editorBridge: editorBridge,
            previewBridge: bridge,
            findController: findController
        ))
        .onAppear {
            findController.attach(editorBridge: editorBridge, previewBridge: bridge, mode: document.mode)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: document.rawText, initial: true) { _, newText in
            guard document.mode == .preview else { return }
            refreshPreviewPreservingScroll(from: newText, ratio: document.scrollRatio)
        }
        .onChange(of: document.mode) { oldMode, newMode in
            findController.activeMode = newMode
            if newMode != .edit {
                findController.showsReplace = false
            }
            let anchorContext = ViewportAnchorSync.Context(
                document: document,
                editorBridge: editorBridge,
                previewBridge: bridge
            )
            if oldMode == .preview && newMode == .edit {
                // Capture the preview center anchor before edit layout settles,
                // then re-center the editor on it.
                ViewportAnchorSync.capture(context: anchorContext) { anchor in
                    guard document.mode == .edit else { return }
                    ViewportAnchorSync.restore(anchor, context: anchorContext)
                }
            } else if newMode == .preview {
                // Capture the editor center anchor and carry it into the preview.
                let anchor = ViewportAnchorSync.Anchor(
                    sourceLine: editorBridge.currentSourceLineAtViewportCenter(),
                    ratio: editorBridge.currentScrollRatio() ?? document.scrollRatio
                )
                document.scrollRatio = anchor.ratio
                refreshPreviewPreservingScroll(
                    from: document.rawText,
                    sourceLine: anchor.sourceLine,
                    ratio: anchor.ratio
                )
            }
        }
        .onChange(of: document.id) { _, _ in
            guard document.mode == .preview else { return }
            refreshPreviewPreservingScroll(from: document.rawText, ratio: document.scrollRatio)
        }
        .onChange(of: scrollToHeading) { _, heading in
            guard document.mode == .preview, let heading else { return }
            bridge.scrollToHeading(heading)
        }
        .onChange(of: colorScheme) { _, _ in
            if document.mode == .preview {
                refreshPreviewPreservingScroll(from: document.rawText, ratio: document.scrollRatio)
            }
        }
    }

    private func refreshPreviewPreservingScroll(
        from text: String,
        sourceLine: Int? = nil,
        ratio: Double
    ) {
        let contentChanged = refreshPreview(from: text)
        bridge.setPendingViewportRestore(
            sourceLine: sourceLine,
            ratio: ratio,
            applyImmediately: !contentChanged
        )
    }

    @discardableResult
    private func refreshPreview(from text: String) -> Bool {
        let themeKey = colorScheme == .dark ? "dark" : "light"
        let cacheCheckSignpost = TabSwitchProfiler.beginInterval(
            "Preview Cache Check",
            document: document,
            active: isSelected
        )
        let needsRender = renderedDocumentID != document.id
            || renderedTextRevision != document.textRevision
            || renderedThemeKey != themeKey
            || bodyHTML.isEmpty
        TabSwitchProfiler.endInterval(
            "Preview Cache Check",
            signpostID: cacheCheckSignpost
        )
        guard needsRender else {
            return false
        }

        renderedDocumentID = document.id
        renderedTextRevision = document.textRevision
        renderedThemeKey = themeKey
        let signpostID = TabSwitchProfiler.beginInterval(
            "Markdown Render",
            document: document,
            active: isSelected
        )
        defer {
            TabSwitchProfiler.endInterval("Markdown Render", signpostID: signpostID)
        }
        let fragment = MarkdownRenderer.renderHTML(from: text)
        bodyHTML = fragment
        let page = HTMLTemplate.currentPage(body: fragment, colorScheme: colorScheme)
        htmlContent = page
        renderedContentRevision &+= 1
        return true
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                document.rawText = text
                document.updateTextMetrics()
                document.fileURL = url
                document.isDirty = false
                document.clearUndoHistory()
                document.headings = HeadingParser.parseHeadings(in: text)
                document.reconcileActiveHeadingWithCurrentContent()
            }
        }
        return true
    }
}

private struct SelectedDocumentFocusValues: ViewModifier {
    let isSelected: Bool
    let editorBridge: EditorBridge
    let previewBridge: PreviewBridge
    let findController: FindController

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.editorBridge, isSelected ? editorBridge : nil)
            .focusedSceneValue(\.previewBridge, isSelected ? previewBridge : nil)
            .focusedSceneValue(\.findController, isSelected ? findController : nil)
    }
}
