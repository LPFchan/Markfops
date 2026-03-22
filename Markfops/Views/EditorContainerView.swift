import SwiftUI

struct EditorContainerView: View {
    @Bindable var document: Document
    var configuration: EditorConfiguration
    var scrollToLine: Int?

    @Environment(\.colorScheme) private var colorScheme
    @State private var htmlContent: String = ""
    @State private var isDragTargeted = false

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
                PreviewView(htmlContent: htmlContent)
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
            if document.mode == .preview {
                refreshPreview(from: newText)
            }
        }
        .onChange(of: document.mode) { _, newMode in
            if newMode == .preview {
                refreshPreview(from: document.rawText)
            }
        }
        // Re-render preview when system appearance changes
        .onChange(of: colorScheme) { _, _ in
            if document.mode == .preview { refreshPreview(from: document.rawText) }
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
