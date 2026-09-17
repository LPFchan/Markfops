import SwiftUI

struct EditorContainerView: View {
    @Bindable var document: Document
    var configuration: EditorConfiguration
    var scrollToHeading: HeadingNode?
    var isSelected = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragTargeted = false
    private var editorBridge: EditorBridge { document.sharedEditorBridge }
    @State private var findController = FindController()

    private var findOverlayReservedTopInset: CGFloat {
        guard findController.isVisible else { return 0 }
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
                isActive: isSelected,
                isVisible: isSelected
            )
            .id(document.id)
            .padding(.top, findOverlayReservedTopInset)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .focusedValue(\.editorBridge, editorBridge)

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
            findController: findController
        ))
        .onAppear {
            findController.attach(editorBridge: editorBridge, mode: document.mode)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: document.mode) { oldMode, newMode in
            findController.modeDidChange(to: newMode)
            editorBridge.mode = newMode

            let context = anchorContext()
            let anchor = ViewportAnchorSync.capture(
                context: context,
                surface: oldMode == .preview ? .reader : .editor
            )
            deliverCursor(anchor.sourceCursor, to: newMode)
            ViewportAnchorSync.restore(
                anchor,
                context: context,
                editorDelay: 0.05
            )
        }
        .onChange(of: scrollToHeading) { _, heading in
            guard let heading else { return }
            editorBridge.scrollToSourceLineCentered(heading.lineNumber)
        }
    }

    private func deliverCursor(_ sourceCursor: Int?, to mode: EditMode) {
        guard let sourceCursor else { return }
        editorBridge.setSourceCursor(sourceCursor)
    }

    private func anchorContext() -> ViewportAnchorSync.Context {
        ViewportAnchorSync.Context(
            document: document,
            editorBridge: editorBridge
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
    let findController: FindController

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.editorBridge, isSelected ? editorBridge : nil)
            .focusedSceneValue(\.findController, isSelected ? findController : nil)
    }
}
