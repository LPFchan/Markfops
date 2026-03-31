import SwiftUI

struct EditorContainerView: View {
    @Bindable var document: Document
    var configuration: EditorConfiguration
    var scrollToHeading: HeadingNode?

    @Environment(\.colorScheme) private var colorScheme
    @State private var htmlContent: String = ""
    @State private var isDragTargeted = false
    @State private var bridge = PreviewBridge()
    @State private var editorBridge = EditorBridge()

    var body: some View {
        Group {
            switch document.mode {
            case .edit:
                EditorView(
                    text: $document.rawText,
                    document: document,
                    configuration: configuration,
                    scrollToLine: scrollToHeading?.lineNumber,
                    editorBridge: editorBridge
                )

            case .preview:
                PreviewView(
                    htmlContent: htmlContent,
                    bridge: bridge,
                    onTextChange: { editedText in
                        // WYSIWYG edits from the viewer arrive here (debounced 400ms)
                        document.rawText = editedText
                        document.updateTextMetrics()
                        document.isDirty = true
                        document.headings = HeadingParser.parseHeadings(in: editedText)
                        document.reconcileActiveHeadingWithCurrentContent()
                    },
                    onScrollChange: { ratio in
                        document.scrollRatio = ratio
                        document.syncActiveHeadingToScrollPosition()
                    }
                )
            }
        }
        .overlay(
            isDragTargeted
                ? RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .allowsHitTesting(false)
                : nil
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: document.rawText, initial: true) { _, newText in
            // Only push a fresh render when the change came from the editor (not from
            // the WYSIWYG view syncing back its own edits) and preview is visible.
            guard document.mode == .preview,
                  bridge.coordinator?.isEditingInView != true else { return }
            refreshPreview(from: newText)
        }
        .onChange(of: document.mode) { oldMode, newMode in
            if oldMode == .preview && newMode == .edit {
                let wasEditing = bridge.coordinator?.isEditingInView ?? false
                if wasEditing {
                    bridge.extractText { text in
                        if !text.isEmpty {
                            document.rawText = text
                            document.updateTextMetrics()
                            document.headings = HeadingParser.parseHeadings(in: text)
                            document.reconcileActiveHeadingWithCurrentContent()
                        }
                        bridge.resetEditingFlag()
                    }
                } else {
                    bridge.resetEditingFlag()
                }
                // Restore editor scroll position after view switches back
                let ratio = document.scrollRatio
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    editorBridge.scrollToRatio(ratio)
                }
            } else if newMode == .preview {
                bridge.setPendingScrollRatio(document.scrollRatio)
                bridge.resetEditingFlag()
                refreshPreview(from: document.rawText)
            }
        }
        .onChange(of: scrollToHeading) { _, heading in
            guard document.mode == .preview, let heading else { return }
            bridge.scrollToHeading(heading)
        }
        .onChange(of: colorScheme) { _, _ in
            if document.mode == .preview {
                bridge.resetEditingFlag()
                refreshPreview(from: document.rawText)
            }
        }
    }

    private func refreshPreview(from text: String) {
        let fragment = MarkdownRenderer.renderHTML(from: text)
        let page = HTMLTemplate.currentPage(body: fragment, colorScheme: colorScheme)
        htmlContent = page
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
                document.headings = HeadingParser.parseHeadings(in: text)
                document.reconcileActiveHeadingWithCurrentContent()
            }
        }
        return true
    }
}
