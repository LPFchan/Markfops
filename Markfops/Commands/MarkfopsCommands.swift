import SwiftUI

struct MarkfopsCommands: Commands {
    @FocusedValue(\.documentStore) private var store

    var body: some Commands {
        // Replace default New Window command
        CommandGroup(replacing: .newItem) {
            Button("New") {
                store?.newDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                store?.newDocument()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Open…") {
                openFile()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                guard let doc = store?.activeDocument else { return }
                try? store?.save(doc)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Save As…") {
                guard let doc = store?.activeDocument else { return }
                try? store?.saveAs(doc)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Close Tab") {
                guard let id = store?.activeID else { return }
                store?.close(id: id)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandMenu("View") {
            Button("Toggle Edit / Preview") {
                guard let doc = store?.activeDocument else { return }
                doc.mode = doc.mode == .edit ? .preview : .edit
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Button("Next Tab") {
                store?.selectNext()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Previous Tab") {
                store?.selectPrevious()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        }

        CommandMenu("Format") {
            Button("Bold") {
                NSApp.sendAction(#selector(NSTextView.wrapBold), to: nil, from: nil)
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Italic") {
                NSApp.sendAction(#selector(NSTextView.wrapItalic), to: nil, from: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Inline Code") {
                NSApp.sendAction(#selector(NSTextView.wrapCode), to: nil, from: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .option])
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!,
            .plainText
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store?.open(url: url) }
    }
}

// MARK: - NSTextView action selectors

extension NSTextView {
    @objc func wrapBold() {
        (self as? MarkdownNSTextView)?.wrapSelection(prefix: "**", suffix: "**")
    }
    @objc func wrapItalic() {
        (self as? MarkdownNSTextView)?.wrapSelection(prefix: "_", suffix: "_")
    }
    @objc func wrapCode() {
        (self as? MarkdownNSTextView)?.wrapSelection(prefix: "`", suffix: "`")
    }
}
