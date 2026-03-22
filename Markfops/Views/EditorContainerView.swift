import SwiftUI

struct EditorContainerView: View {
    @Bindable var document: Document
    var configuration: EditorConfiguration
    var scrollToLine: Int?

    @Environment(\.colorScheme) private var colorScheme
    @State private var htmlContent: String = ""
    @State private var isDragTargeted = false
    @State private var bridge = PreviewBridge()

    var body: some View {
        Group {
            switch document.mode {
            case .edit:
                EditorView(
                    text: $document.rawText,
                    document: document,
                    configuration: configuration,
                    scrollToLine: scrollToLine
                )

            case .preview:
                PreviewView(htmlContent: htmlContent, bridge: bridge) { editedText in
                    // WYSIWYG edits from the viewer arrive here (debounced 400ms)
                    document.rawText = editedText
                    document.isDirty = true
                    // Update headings so sidebar TOC stays in sync
                    document.headings = HeadingParser.parseHeadings(in: editedText)
                }
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
                // Extract final viewer text before handing off to NSTextView
                bridge.extractText { text in
                    if !text.isEmpty {
                        document.rawText = text
                        document.headings = HeadingParser.parseHeadings(in: text)
                    }
                    bridge.resetEditingFlag()
                }
            } else if newMode == .preview {
                bridge.resetEditingFlag()
                refreshPreview(from: document.rawText)
            }
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
        htmlContent = HTMLTemplate.currentPage(body: fragment, colorScheme: colorScheme)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                document.rawText = text
                document.fileURL = url
                document.isDirty = false
                document.headings = HeadingParser.parseHeadings(in: text)
            }
        }
        return true
    }
}
