import SwiftUI

struct EditorContainerView: View {
    @Bindable var document: Document
    var configuration: EditorConfiguration
    var scrollToHeading: HeadingNode?
    var isSelected = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragTargeted = false
    private var editorBridge: EditorBridge { document.sharedEditorBridge }
    private var readerBridge: ReaderBridge { document.sharedReaderBridge }
    @State private var findController = FindController()

    private var findOverlayReservedTopInset: CGFloat {
        guard document.mode == .edit, findController.isVisible else { return 0 }
        return findController.showsReplace ? 122 : 74
    }

    var body: some View {
        ZStack(alignment: .top) {
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

            ReaderView(
                document: document,
                theme: ReaderTheme.default,
                themeKey: colorScheme == .dark ? "dark" : "light",
                readerBridge: readerBridge,
                isActive: isSelected && document.mode == .preview
            )
            .id(document.id)
            .padding(.top, findOverlayReservedTopInset)
            .opacity(document.mode == .preview ? 1 : 0)
            .allowsHitTesting(document.mode == .preview)
            .accessibilityHidden(document.mode != .preview)
            .focusedValue(\.readerBridge, readerBridge)

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
            readerBridge: readerBridge,
            findController: findController
        ))
        .onAppear {
            findController.attach(editorBridge: editorBridge, mode: document.mode)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: document.mode) { oldMode, newMode in
            findController.activeMode = newMode
            if newMode == .preview {
                findController.hide()
            }

            let sourceSurface: ViewportAnchorSync.Surface = oldMode == .preview
                ? .reader
                : .editor
            let context = anchorContext()
            let anchor = ViewportAnchorSync.capture(
                context: context,
                surface: sourceSurface
            )
            ViewportAnchorSync.restore(anchor, context: context)
        }
        .onChange(of: scrollToHeading) { _, heading in
            guard document.mode == .preview, let heading else { return }
            readerBridge.scrollToHeading(heading)
        }
    }

    private func anchorContext() -> ViewportAnchorSync.Context {
        ViewportAnchorSync.Context(
            document: document,
            editorBridge: editorBridge,
            readerBridge: readerBridge
        )
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
                document.headings = MarkdownSourceMap.parse(text).headings
                document.reconcileActiveHeadingWithCurrentContent()
            }
        }
        return true
    }
}

private struct SelectedDocumentFocusValues: ViewModifier {
    let isSelected: Bool
    let editorBridge: EditorBridge
    let readerBridge: ReaderBridge
    let findController: FindController

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.editorBridge, isSelected ? editorBridge : nil)
            .focusedSceneValue(\.readerBridge, isSelected ? readerBridge : nil)
            .focusedSceneValue(\.findController, isSelected ? findController : nil)
    }
}
