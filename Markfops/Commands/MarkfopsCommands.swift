import SwiftUI

struct MarkfopsCommands: Commands {
    @FocusedValue(\.documentStore) private var store

    var body: some Commands {
        // MARK: File menu
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

        CommandGroup(after: .newItem) {
            Menu("Open Recent") {
                let recents = NSDocumentController.shared.recentDocumentURLs
                if recents.isEmpty {
                    Text("No Recent Documents").foregroundColor(.secondary)
                } else {
                    ForEach(recents.prefix(10), id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            store?.open(url: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                    }
                }
            }
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

            Button("Duplicate") {
                guard let doc = store?.activeDocument else { return }
                store?.duplicate(doc)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Rename…") {
                guard let doc = store?.activeDocument else { return }
                store?.rename(doc)
            }

            Button("Move To…") {
                guard let doc = store?.activeDocument else { return }
                store?.moveTo(doc)
            }

            Divider()

            Button("Revert to Saved") {
                guard let doc = store?.activeDocument else { return }
                store?.revertToSaved(doc)
            }
            .disabled(store?.activeDocument?.fileURL == nil || store?.activeDocument?.isDirty == false)

            Divider()

            Button("Print…") {
                NSApp.sendAction(#selector(NSView.printView(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Export as PDF…") {
                guard let doc = store?.activeDocument else { return }
                store?.exportAsPDF(doc)
            }

            Divider()

            Button("Close Tab") {
                guard let id = store?.activeID else { return }
                store?.close(id: id)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        // MARK: Find (Edit menu, after pasteboard group)
        CommandGroup(after: .pasteboard) {
            Menu("Find") {
                Button("Find…") { triggerFinder(.showFindInterface) }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(store?.activeDocument?.mode != .edit)

                Button("Find and Replace…") { triggerFinder(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(store?.activeDocument?.mode != .edit)

                Divider()

                Button("Find Next") { triggerFinder(.nextMatch) }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(store?.activeDocument?.mode != .edit)

                Button("Find Previous") { triggerFinder(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(store?.activeDocument?.mode != .edit)

                Button("Use Selection for Find") { triggerFinder(.setSearchString) }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(store?.activeDocument?.mode != .edit)
            }
        }

        // MARK: View menu — inject after the built-in toolbar group to avoid creating a duplicate "View" menu
        CommandGroup(after: .toolbar) {
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

            Divider()

            // Cmd+1…9: switch to tab N; Cmd+0: switch to last tab
            Button("Select Tab 1") { store?.selectTab(at: 0) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 1)
            Button("Select Tab 2") { store?.selectTab(at: 1) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 2)
            Button("Select Tab 3") { store?.selectTab(at: 2) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 3)
            Button("Select Tab 4") { store?.selectTab(at: 3) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 4)
            Button("Select Tab 5") { store?.selectTab(at: 4) }
                .keyboardShortcut("5", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 5)
            Button("Select Tab 6") { store?.selectTab(at: 5) }
                .keyboardShortcut("6", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 6)
            Button("Select Tab 7") { store?.selectTab(at: 6) }
                .keyboardShortcut("7", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 7)
            Button("Select Tab 8") { store?.selectTab(at: 7) }
                .keyboardShortcut("8", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 8)
            Button("Select Tab 9") { store?.selectTab(at: 8) }
                .keyboardShortcut("9", modifiers: .command)
                .disabled((store?.documents.count ?? 0) < 9)
            Button("Select Last Tab") { store?.activeID = store?.documents.last?.id }
                .keyboardShortcut("0", modifiers: .command)
                .disabled((store?.documents.count ?? 0) == 0)

            Divider()

            Button("Increase Font Size") {
                let size = UserDefaults.standard.double(forKey: "editorFontSize")
                UserDefaults.standard.set(min((size > 0 ? size : 15) + 1, 32), forKey: "editorFontSize")
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Decrease Font Size") {
                let size = UserDefaults.standard.double(forKey: "editorFontSize")
                UserDefaults.standard.set(max((size > 0 ? size : 15) - 1, 10), forKey: "editorFontSize")
            }
            .keyboardShortcut("-", modifiers: .command)
        }

        // MARK: Format menu
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

            Divider()

            // Paste and Match Style — strips RTF/rich formatting, inserts plain text.
            // In Edit mode: handled natively by NSTextView (pasteAsPlainText:).
            // In Preview/WYSIWYG mode: enforced automatically via the JS paste interceptor.
            Button("Paste and Match Style") {
                NSApp.sendAction(#selector(NSTextView.pasteAsPlainText(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .option, .shift])
        }
    }

    /// Forwards a text finder action to the first responder regardless of current focus.
    private func triggerFinder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
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

// MARK: - NSTextView formatting selectors

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
